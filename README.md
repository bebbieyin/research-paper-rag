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
