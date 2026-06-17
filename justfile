set dotenv-load := true

port := env_var("PORT")
local_url := "http://127.0.0.1:" + port
data_dir := env_var("DATA_DIR")
service := env_var("SERVICE")
region := env_var("REGION")
repository := env_var("REPOSITORY")
project_id := env_var("PROJECT_ID")
cloud_run_memory := env_var("CLOUD_RUN_MEMORY")
cloud_run_cpu := env_var("CLOUD_RUN_CPU")
cloud_run_timeout := env_var("CLOUD_RUN_TIMEOUT")
cloud_run_job_timeout := env_var("CLOUD_RUN_JOB_TIMEOUT")
pinecone_index_name := env_var("PINECONE_INDEX_NAME")
pinecone_namespace := env_var("PINECONE_NAMESPACE")
hf_embedding_model := env_var("HF_EMBEDDING_MODEL")
hf_embedding_dimension := env_var("HF_EMBEDDING_DIMENSION")
hf_chat_model := env_var("HF_CHAT_MODEL")
hf_provider := env_var("HF_PROVIDER")
pinecone_rerank_model := env_var("PINECONE_RERANK_MODEL")
chunk_size := env_var("CHUNK_SIZE")
chunk_overlap := env_var("CHUNK_OVERLAP")
retrieval_top_k := env_var("RETRIEVAL_TOP_K")
rerank_top_n := env_var("RERANK_TOP_N")
index_upsert_batch_size := env_var_or_default("INDEX_UPSERT_BATCH_SIZE", "100")
commit_sha := `git rev-parse --short HEAD`
deploy_stamp := `date -u +%Y%m%d%H%M%S`
revision_suffix := commit_sha + "-" + deploy_stamp
image := region + "-docker.pkg.dev/" + project_id + "/" + repository + "/" + service + ":" + commit_sha
index_job := service + "-indexer"
runtime_env := "PROJECT_ID=" + project_id + ",GCS_BUCKET=$GCS_BUCKET,GCS_PREFIX=$GCS_PREFIX,PINECONE_INDEX_NAME=" + pinecone_index_name + ",PINECONE_NAMESPACE=" + pinecone_namespace + ",HF_EMBEDDING_MODEL=" + hf_embedding_model + ",HF_EMBEDDING_DIMENSION=" + hf_embedding_dimension + ",HF_CHAT_MODEL=" + hf_chat_model + ",HF_PROVIDER=" + hf_provider + ",PINECONE_RERANK_MODEL=" + pinecone_rerank_model + ",CHUNK_SIZE=" + chunk_size + ",CHUNK_OVERLAP=" + chunk_overlap + ",RETRIEVAL_TOP_K=" + retrieval_top_k + ",RERANK_TOP_N=" + rerank_top_n + ",INDEX_UPSERT_BATCH_SIZE=" + index_upsert_batch_size + ",COMMIT_SHA=" + commit_sha

# Show the main workflow commands.
default:
    @echo "Main workflow:"
    @echo "  just data-refresh                 # sync PDFs to Cloud Storage and run indexing job"
    @echo "  just deploy-local                 # rebuild and run the app locally with Docker"
    @echo "  just run-local                    # run the app locally without Docker"
    @echo "  just test                         # run pytest"
    @echo "  just health                       # call local /health"
    @echo "  just ask \"question\"               # call local /ask"
    @echo "  just deploy-production            # build, push, and deploy to Cloud Run"
    @echo "  just cloud-ask \"question\"         # call Cloud Run /ask"
    @echo ""
    @echo "Useful:"
    @echo "  just logs                         # follow local Docker logs"
    @echo "  just stop                         # stop local Docker app"
    @echo "  just cloud-logs                   # show recent Cloud Run service logs"
    @echo "  just index-job-logs               # show recent Cloud Run indexing job logs"
    @echo "  just cloud-url                    # print Cloud Run URL"
    @echo "  just data-list                    # list PDFs in Cloud Storage"
    @echo "  just setup-bucket                 # one-time bucket setup"
    @echo "  just grant-secret-access          # one-time Secret Manager access setup"
    @echo ""
    @echo "All commands:"
    @just --list --unsorted

# Rebuild and run the app locally with Docker after code changes.
deploy-local: test
    docker compose up --build -d
    @echo "Local API: {{local_url}}"

# Run the app locally without Docker.
run-local:
    uv run uvicorn src.main:app --host 127.0.0.1 --port 8000 --reload

# Run the test suite.
test:
    uv run --group test pytest

# Build, push, and deploy the app and indexing job to Cloud Run.
deploy-production: test _require-committed _cloud-build _cloud-push _cloud-deploy _cloud-job-deploy

# Call the local health endpoint.
health:
    curl {{local_url}}/health

# Ask a question against the local API.
ask question:
    curl -X POST {{local_url}}/ask \
      -H "Content-Type: application/json" \
      -d '{"question":"{{question}}"}'

# Stop the Dockerized API.
stop:
    docker compose down

# Follow API logs from Docker Compose.
logs:
    docker compose logs -f api

# Build the image for GCP Artifact Registry.
[private]
_cloud-build:
    docker build --platform linux/amd64 -t "{{image}}" .

# Push the image to GCP Artifact Registry.
[private]
_cloud-push:
    docker push "{{image}}"

# Require deployment from a committed, clean working tree.
[private]
_require-committed:
    @test -z "$(git status --porcelain)" || (echo "There are files not committed yet. Commit or stash changes before deploying." && exit 1)

# Grant Cloud Run's runtime service account access to Secret Manager secrets.
grant-secret-access:
    PROJECT_NUMBER="$(gcloud projects describe "{{project_id}}" --format='value(projectNumber)')" && \
    RUNTIME_SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com" && \
    gcloud secrets add-iam-policy-binding pinecone-api-key \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role="roles/secretmanager.secretAccessor" && \
    gcloud secrets add-iam-policy-binding huggingfacehub-api-token \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role="roles/secretmanager.secretAccessor"

# Create the Cloud Storage bucket for PDFs. Set GCS_BUCKET in .env first.
[private]
_gcs-create-bucket:
    test -n "$GCS_BUCKET" || (echo "Set GCS_BUCKET in .env first." && exit 1)
    gcloud storage buckets create "gs://$GCS_BUCKET" \
      --project "{{project_id}}" \
      --location "{{region}}" \
      --uniform-bucket-level-access

# Grant Cloud Run's runtime service account read access to the PDF bucket.
[private]
_gcs-grant-cloud-run-read:
    test -n "$GCS_BUCKET" || (echo "Set GCS_BUCKET in .env first." && exit 1)
    PROJECT_NUMBER="$(gcloud projects describe "{{project_id}}" --format='value(projectNumber)')" && \
    RUNTIME_SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com" && \
    gcloud storage buckets add-iam-policy-binding "gs://$GCS_BUCKET" \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role="roles/storage.objectViewer"

# One-time bucket setup: create the bucket and grant Cloud Run read access.
setup-bucket: _gcs-create-bucket _gcs-grant-cloud-run-read

# Sync local PDFs/data from DATA_DIR to gs://GCS_BUCKET/GCS_PREFIX/.
[private]
_gcs-upload-pdfs:
    test -n "$GCS_BUCKET" || (echo "Set GCS_BUCKET in .env first." && exit 1)
    test -n "$GCS_PREFIX" || (echo "Set GCS_PREFIX in .env first." && exit 1)
    gcloud storage rsync "{{data_dir}}" "gs://$GCS_BUCKET/$GCS_PREFIX/" --recursive

# List PDFs in the configured Cloud Storage bucket prefix.
data-list:
    test -n "$GCS_BUCKET" || (echo "Set GCS_BUCKET in .env first." && exit 1)
    test -n "$GCS_PREFIX" || (echo "Set GCS_PREFIX in .env first." && exit 1)
    gcloud storage ls "gs://$GCS_BUCKET/$GCS_PREFIX/"

# Sync PDFs to Cloud Storage and index them with a Cloud Run Job.
data-refresh: _gcs-upload-pdfs _cloud-index

# Deploy the latest pushed image to Cloud Run. Set PROJECT_ID in .env first.
[private]
_cloud-deploy:
    gcloud run deploy "{{service}}" \
      --image "{{image}}" \
      --region "{{region}}" \
      --allow-unauthenticated \
      --port 8000 \
      --memory "{{cloud_run_memory}}" \
      --cpu "{{cloud_run_cpu}}" \
      --timeout "{{cloud_run_timeout}}" \
      --min-instances 0 \
      --max-instances 2 \
      --revision-suffix "{{revision_suffix}}" \
      --labels commit-sha="{{commit_sha}}" \
      --set-env-vars "{{runtime_env}}" \
      --set-secrets PINECONE_API_KEY=pinecone-api-key:latest,HUGGINGFACEHUB_API_TOKEN=huggingfacehub-api-token:latest,HF_TOKEN=huggingfacehub-api-token:latest

# Deploy the indexing worker as a Cloud Run Job. It uses the same image as the API.
[private]
_cloud-job-deploy:
    gcloud run jobs deploy "{{index_job}}" \
      --image "{{image}}" \
      --region "{{region}}" \
      --memory "{{cloud_run_memory}}" \
      --cpu "{{cloud_run_cpu}}" \
      --task-timeout "{{cloud_run_job_timeout}}" \
      --max-retries 0 \
      --labels commit-sha="{{commit_sha}}" \
      --set-env-vars "{{runtime_env}}" \
      --set-secrets PINECONE_API_KEY=pinecone-api-key:latest,HUGGINGFACEHUB_API_TOKEN=huggingfacehub-api-token:latest,HF_TOKEN=huggingfacehub-api-token:latest \
      --command uv \
      --args run,--no-sync,python,-m,src.index_job

# Print the deployed Cloud Run service URL.
cloud-url:
    gcloud run services describe "{{service}}" --region "{{region}}" --format='value(status.url)'

# Index PDFs from the configured Cloud Storage bucket using the Cloud Run Job.
[private]
_cloud-index:
    gcloud run jobs execute "{{index_job}}" --region "{{region}}" --wait

# Ask a question against the Cloud Run API.
cloud-ask question:
    SERVICE_URL="$(gcloud run services describe "{{service}}" --region "{{region}}" --format='value(status.url)')" && \
    curl -X POST "$SERVICE_URL/ask" \
      -H "Content-Type: application/json" \
      -d '{"question":"{{question}}"}'

# Show recent Cloud Run logs for this service.
cloud-logs:
    gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="{{service}}"' \
      --project "{{project_id}}" \
      --limit 50 \
      --format "value(timestamp,severity,textPayload)"

# Show recent Cloud Run logs for the indexing job.
index-job-logs:
    gcloud logging read 'resource.type="cloud_run_job" AND resource.labels.job_name="{{index_job}}"' \
      --project "{{project_id}}" \
      --limit 100 \
      --format "value(timestamp,severity,textPayload)"
