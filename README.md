## Research Paper RAG API

The API has two main production steps:

1. Sync PDFs to Cloud Storage and index them into Pinecone.
2. Ask questions against the indexed paper chunks.

### Setup

Create `.env` from the example and fill in your real values.

```bash
cp .env.example .env
```

One-time cloud storage setup:

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

When PDFs change, refresh the remote data first:

```bash
just data-refresh
```

`just data-refresh` expects the Cloud Run indexing job to exist. Run
`just deploy-production` after code or deployment configuration changes so both
the API service and indexing job are updated.

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

`just data-refresh` syncs local `DATA_DIR` to Cloud Storage and runs a Cloud
Run Job to index the bucket PDFs into Pinecone. `just deploy-production` builds
the image, deploys the Cloud Run API, and creates or updates the indexing job.

The local Docker app and Cloud Run API both answer from the shared Pinecone
index. PDF indexing is handled by the Cloud Run indexing job, which reads
`GCS_BUCKET` and `GCS_PREFIX`.

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

Ask a question:

```bash
curl -X POST http://127.0.0.1:8000/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"What are the categories of attentional models?"}'
```
