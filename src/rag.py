"""Minimal production RAG pipeline for research papers."""

from functools import lru_cache
from os import getenv
from pathlib import Path
from typing import Protocol
from uuid import NAMESPACE_URL, uuid5

from dotenv import load_dotenv
from langchain_community.document_loaders import DirectoryLoader, PyMuPDFLoader
from langchain_core.documents import Document
from langchain_core.output_parsers import PydanticOutputParser
from langchain_core.prompts import ChatPromptTemplate
from langchain_huggingface import (
    ChatHuggingFace,
    HuggingFaceEmbeddings,
    HuggingFaceEndpoint,
)
from langchain_pinecone import PineconeVectorStore
from langchain_text_splitters import RecursiveCharacterTextSplitter
from pinecone import Pinecone, ServerlessSpec

from src.schema import InsertResponse, QuestionAnswer

load_dotenv()


def required_env(name: str) -> str:
    """Return a required environment variable or fail with a clear message."""
    value = getenv(name)
    if value is None or value == "":
        message = f"Missing required environment variable: {name}"
        raise RuntimeError(message)
    return value


def required_int_env(name: str) -> int:
    """Return a required integer environment variable."""
    return int(required_env(name))


INDEX_NAME = required_env("PINECONE_INDEX_NAME")
NAMESPACE = required_env("PINECONE_NAMESPACE")

EMBEDDING_MODEL = required_env("HF_EMBEDDING_MODEL")
EMBEDDING_DIMENSION = required_int_env("HF_EMBEDDING_DIMENSION")

CHAT_MODEL_ID = required_env("HF_CHAT_MODEL")
HF_PROVIDER = required_env("HF_PROVIDER")
RERANK_MODEL = required_env("PINECONE_RERANK_MODEL")

CHUNK_SIZE = required_int_env("CHUNK_SIZE")
CHUNK_OVERLAP = required_int_env("CHUNK_OVERLAP")
RETRIEVAL_TOP_K = required_int_env("RETRIEVAL_TOP_K")
RERANK_TOP_N = required_int_env("RERANK_TOP_N")

ANSWER_PROMPT = ChatPromptTemplate.from_messages(
    [
        (
            "system",
            "You answer questions about research papers. Use only the provided "
            "context. If the context is insufficient, say you are unsure. "
            "Include concise citations.\n\n"
            "{format_instructions}",
        ),
        ("human", "Question:\n{question}\n\nRetrieved context:\n{context}"),
    ],
)


class AnswerChain(Protocol):
    """Small protocol for the cached LangChain object used by this module."""

    def invoke(self, input_data: dict[str, str]) -> QuestionAnswer:
        """Run the chain."""


def project_root() -> Path:
    """Return the repository root when running from the repo or from notebooks."""
    cwd = Path.cwd()
    if (cwd / "data").exists():
        return cwd
    if (cwd.parent / "data").exists():
        return cwd.parent
    return cwd


def data_dir() -> Path:
    """Return the PDF data directory."""
    return Path(required_env("DATA_DIR"))


def stable_chunk_id(doc: Document) -> str:
    """Create a repeatable Pinecone ID for a chunk."""
    source = doc.metadata.get("source", "unknown")
    page = doc.metadata.get("page", "unknown")
    chunk_number = doc.metadata.get("chunk_number", "unknown")
    content_fingerprint = doc.page_content[:200]
    return str(
        uuid5(NAMESPACE_URL, f"{source}:{page}:{chunk_number}:{content_fingerprint}")
    )


def load_pdf_chunks() -> tuple[int, list[Document]]:
    """Load PDFs from DATA_DIR and split them into indexed chunks."""
    loader = DirectoryLoader(
        str(data_dir()),
        glob="**/*.pdf",
        loader_cls=PyMuPDFLoader,
        show_progress=False,
    )
    pages = loader.load()

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
        separators=["\n\n", "\n", ". ", " ", ""],
    )
    chunks = splitter.split_documents(pages)

    for chunk_number, doc in enumerate(chunks):
        source_path = Path(str(doc.metadata.get("source", "unknown")))
        page = doc.metadata.get("page")
        doc.metadata.update(
            {
                "source": source_path.name,
                "source_path": str(source_path),
                "page": int(page) + 1 if isinstance(page, int) else page,
                "chunk_number": chunk_number,
                "namespace": NAMESPACE,
            }
        )

    return len(pages), chunks


@lru_cache(maxsize=1)
def pinecone_client() -> Pinecone:
    """Return a cached Pinecone client."""
    return Pinecone(api_key=required_env("PINECONE_API_KEY"))


def ensure_index() -> object:
    """Create the Pinecone index if it does not exist, then return it."""
    pc = pinecone_client()
    if not pc.has_index(INDEX_NAME):
        pc.create_index(
            name=INDEX_NAME,
            vector_type="dense",
            dimension=EMBEDDING_DIMENSION,
            metric="cosine",
            spec=ServerlessSpec(cloud="aws", region="us-east-1"),
            deletion_protection="disabled",
            tags={
                "project": "research-paper-rag",
                "embedding_model": EMBEDDING_MODEL,
            },
        )
    return pc.Index(INDEX_NAME)


@lru_cache(maxsize=1)
def embeddings() -> HuggingFaceEmbeddings:
    """Return the embedding model used for retrieval."""
    return HuggingFaceEmbeddings(
        model_name=EMBEDDING_MODEL,
        encode_kwargs={"normalize_embeddings": True, "batch_size": 32},
    )


@lru_cache(maxsize=1)
def vector_store() -> PineconeVectorStore:
    """Return a cached vector store."""
    return PineconeVectorStore(
        index=ensure_index(),
        embedding=embeddings(),
        namespace=NAMESPACE,
    )


def insert_papers() -> InsertResponse:
    """Index all PDFs in DATA_DIR."""
    loaded_pages, chunks = load_pdf_chunks()
    if chunks:
        vector_store().add_documents(
            chunks,
            ids=[stable_chunk_id(doc) for doc in chunks],
        )
    return InsertResponse(
        loaded_pages=loaded_pages,
        indexed_chunks=len(chunks),
        namespace=NAMESPACE,
    )


def format_source(doc: Document) -> str:
    """Format a source label for LLM context."""
    source = doc.metadata.get("source", "unknown")
    page = doc.metadata.get("page", "unknown")
    chunk = doc.metadata.get("chunk_number", "unknown")
    score = doc.metadata.get("rerank_score")
    score_text = f", rerank={score:.4f}" if isinstance(score, float) else ""
    return f"{source}, page {page}, chunk {chunk}{score_text}"


def rerank_documents(query: str, docs: list[Document]) -> list[Document]:
    """Rerank retrieved documents with Pinecone inference when available."""
    if not docs:
        return []

    rerank_inputs = [
        {
            "id": str(index),
            "chunk_text": doc.page_content,
            "source": doc.metadata.get("source", "unknown"),
            "page": doc.metadata.get("page", "unknown"),
        }
        for index, doc in enumerate(docs)
    ]

    try:
        result = pinecone_client().inference.rerank(
            model=RERANK_MODEL,
            query=query,
            documents=rerank_inputs,
            top_n=min(RERANK_TOP_N, len(rerank_inputs)),
            rank_fields=["chunk_text"],
            return_documents=True,
            parameters={"truncate": "END"},
        )
    except Exception:
        return docs[:RERANK_TOP_N]

    reranked = []
    for item in result.data:
        doc = docs[item.index]
        doc.metadata["rerank_score"] = float(item.score)
        reranked.append(doc)
    return reranked


def retrieve(query: str) -> list[Document]:
    """Retrieve and rerank relevant chunks for a question."""
    docs = vector_store().similarity_search(
        query,
        k=RETRIEVAL_TOP_K,
        namespace=NAMESPACE,
    )
    return rerank_documents(query, docs)


def format_context(docs: list[Document]) -> str:
    """Format retrieved documents for the answer prompt."""
    return "\n\n".join(
        f"[Source {index}] {format_source(doc)}\n{doc.page_content}"
        for index, doc in enumerate(docs, start=1)
    )


@lru_cache(maxsize=1)
def rag_chain() -> AnswerChain:
    """Return the cached answer-generation chain."""
    parser = PydanticOutputParser(pydantic_object=QuestionAnswer)
    llm = HuggingFaceEndpoint(
        repo_id=CHAT_MODEL_ID,
        task="text-generation",
        provider=HF_PROVIDER,
        max_new_tokens=700,
        do_sample=False,
        repetition_penalty=1.03,
    )
    return ANSWER_PROMPT | ChatHuggingFace(llm=llm) | parser


def answer_question(question: str) -> QuestionAnswer:
    """Answer a question using retrieved paper chunks."""
    parser = PydanticOutputParser(pydantic_object=QuestionAnswer)
    docs = retrieve(question)
    return rag_chain().invoke(
        {
            "question": question,
            "context": format_context(docs),
            "format_instructions": parser.get_format_instructions(),
        }
    )
