## Research Paper RAG API

The API has two main production steps:

1. Sync PDFs to Cloud Storage and index them into Pinecone.
2. Ask questions against the indexed paper chunks.

### Setup

Create `.env` from the example and fill in your real values.

```bash
cp .env.example .env
```

One-time cloud setup:

```bash
just grant-secret-access
just setup-bucket
```

### Workflow

This repo uses `just` for the main local and cloud workflow.

List available commands:

```bash
just
```

When PDFs change, refresh the data first:

```bash
just data-refresh
```

Then make code changes and test locally:

```bash
just deploy-local
just health
just ask "What are the categories of attentional models?"
```

Deploy to Cloud Run and test the cloud API:

```bash
just deploy-production
just cloud-ask "What are the categories of attentional models?"
```

Useful checks:

```bash
just logs
just cloud-logs
just data-list
just cloud-url
```

Stop the local Docker app:

```bash
just stop
```

`just data-refresh` syncs local `DATA_DIR` to Cloud Storage and asks Cloud Run
to index the bucket PDFs into Pinecone. `just deploy-production` is only for
shipping code changes.

The local Docker app reads PDFs from local `DATA_DIR`; Cloud Run reads PDFs
from `GCS_BUCKET` and `GCS_PREFIX`.

### Short Version

```bash
just data-refresh  # when PDFs changed
# make code changes
just deploy-local
just health
just ask "What are the categories of attentional models?"
just deploy-production
just cloud-ask "What are the categories of attentional models?"
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
