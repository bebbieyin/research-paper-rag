## Research Paper RAG API

Minimal FastAPI service extracted from `notebooks/Research paper RAG.ipynb`.

The API has two production steps:

1. Index PDFs from `data/` into Pinecone.
2. Ask questions against the indexed paper chunks.

### Run

Create `.env`:

```env
PINECONE_API_KEY=...
HUGGINGFACEHUB_API_TOKEN=...
```

Start the API:

```bash
uv run uvicorn src.main:app --reload
```

### Endpoints

Health check:

```bash
curl http://127.0.0.1:8000/health
```

Index PDFs:

```bash
curl -X POST http://127.0.0.1:8000/insert
```

Ask a question:

```bash
curl -X POST http://127.0.0.1:8000/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"What are the categories of attentional models?"}'
```

`POST /answer-question` is kept as an alias for `/ask`.

### Configuration

Optional `.env` overrides:

```env
DATA_DIR=data
PINECONE_INDEX_NAME=research-paper-rag-bge-m3
PINECONE_NAMESPACE=papers-v1
PINECONE_RERANK_MODEL=bge-reranker-v2-m3
HF_EMBEDDING_MODEL=BAAI/bge-m3
HF_EMBEDDING_DIMENSION=1024
HF_CHAT_MODEL=deepseek-ai/DeepSeek-V4-Pro
HF_PROVIDER=auto
CHUNK_SIZE=900
CHUNK_OVERLAP=150
RETRIEVAL_TOP_K=20
RERANK_TOP_N=5
```
