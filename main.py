"""RAG pipeline API using LangChain and FastAPI."""

from fastapi import FastAPI
from langchain_community.embeddings import HuggingFaceBgeEmbeddings
from langchain_community.llms import HuggingFaceHub
from langchain_core.output_parsers import JsonOutputParser
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import RunnableParallel, RunnablePassthrough
from langchain_pinecone import PineconeVectorStore

from schema import QuestionAnswer, QuestionData

model_name = "BAAI/bge-small-en"
model_kwargs = {"device": "cpu"}
encode_kwargs = {"normalize_embeddings": True}
embedding_function = HuggingFaceBgeEmbeddings(
    model_name=model_name,
    model_kwargs=model_kwargs,
    encode_kwargs=encode_kwargs,
)

# load open-source chat model from Huggingface
chat_model = HuggingFaceHub(
    repo_id="meta-llama/Meta-Llama-3-8B-Instruct",
    task="text-generation",
    model_kwargs={
        "temperature": 0.001,
        "return_full_text": False,
    },
)

index_name = "research-paper-index"
vectorstore = PineconeVectorStore(
    index_name=index_name,
    embedding=embedding_function,
)

retriever = vectorstore.as_retriever(search_type="similarity", search_kwargs={"k": 1})

rag_template_with_context = """Answer the question based on the context below.
Keep the answer short and concise.
Respond "Unsure about answer" if not sure about the answer.

Context: {context}
Question: {question}

{format_instructions}

"""


def format_docs(docs: list) -> str:
    """Format a list of documents into a single string."""
    return "\n\n".join(doc.page_content for doc in docs)


parser = JsonOutputParser(pydantic_object=QuestionAnswer)
format_instructions = parser.get_format_instructions()

rag_prompt_with_context = PromptTemplate.from_template(
    template=rag_template_with_context,
    partial_variables={"format_instructions": parser.get_format_instructions()},
)

rag_chain_with_context_from_docs = (
    RunnablePassthrough.assign(context=(lambda x: format_docs(x["context"])))
    | rag_prompt_with_context
    | chat_model
    | parser
)

rag_chain_with_source = RunnableParallel(
    {"context": retriever, "question": RunnablePassthrough()},
).assign(answer=rag_chain_with_context_from_docs)

app = FastAPI()


@app.post("/answer_question", response_model=QuestionAnswer)
def answer_question(question_data: QuestionData) -> dict:
    """Answer a question using the RAG pipeline."""
    response = rag_chain_with_source.invoke(question_data.question)
    return {"response": response}
