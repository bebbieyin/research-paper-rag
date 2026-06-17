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
cloud_run_data_dir := env_var("CLOUD_RUN_DATA_DIR")
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
image := region + "-docker.pkg.dev/" + project_id + "/" + repository + "/" + service + ":latest"

# Show the main workflow commands.
default:
    @echo "Main workflow:"
    @echo "  just data-refresh                 # sync PDFs to Cloud Storage and index them"
    @echo "  just deploy-local                 # rebuild and run the app locally with Docker"
    @echo "  just health                       # call local /health"
    @echo "  just ask \"question\"               # call local /ask"
    @echo "  just deploy-production            # build, push, and deploy to Cloud Run"
    @echo "  just cloud-ask \"question\"         # call Cloud Run /ask"
    @echo ""
    @echo "Useful:"
    @echo "  just logs                         # follow local Docker logs"
    @echo "  just stop                         # stop local Docker app"
    @echo "  just cloud-logs                   # show recent Cloud Run logs"
    @echo "  just cloud-url                    # print Cloud Run URL"
    @echo "  just data-list                    # list PDFs in Cloud Storage"
    @echo "  just setup-bucket                 # one-time bucket setup"
    @echo "  just grant-secret-access          # one-time Secret Manager access setup"
    @echo ""
    @echo "All commands:"
    @just --list --unsorted

# Rebuild and run the app locally with Docker after code changes.
deploy-local:
    docker compose up --build -d
    @echo "Local API: {{local_url}}"

# Build, push, and deploy the app to Cloud Run.
deploy-production: _cloud-build _cloud-push _cloud-deploy

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

# Sync PDFs to Cloud Storage and index them through the Cloud Run API.
data-refresh: _gcs-upload-pdfs _cloud-insert

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
      --min-instances 0 \
      --max-instances 2 \
      --set-env-vars PROJECT_ID="{{project_id}}",DATA_DIR="{{cloud_run_data_dir}}",GCS_BUCKET="$GCS_BUCKET",GCS_PREFIX="$GCS_PREFIX",PINECONE_INDEX_NAME="{{pinecone_index_name}}",PINECONE_NAMESPACE="{{pinecone_namespace}}",HF_EMBEDDING_MODEL="{{hf_embedding_model}}",HF_EMBEDDING_DIMENSION="{{hf_embedding_dimension}}",HF_CHAT_MODEL="{{hf_chat_model}}",HF_PROVIDER="{{hf_provider}}",PINECONE_RERANK_MODEL="{{pinecone_rerank_model}}",CHUNK_SIZE="{{chunk_size}}",CHUNK_OVERLAP="{{chunk_overlap}}",RETRIEVAL_TOP_K="{{retrieval_top_k}}",RERANK_TOP_N="{{rerank_top_n}}" \
      --set-secrets PINECONE_API_KEY=pinecone-api-key:latest,HUGGINGFACEHUB_API_TOKEN=huggingfacehub-api-token:latest,HF_TOKEN=huggingfacehub-api-token:latest

# Print the deployed Cloud Run service URL.
cloud-url:
    gcloud run services describe "{{service}}" --region "{{region}}" --format='value(status.url)'

# Index PDFs from the configured Cloud Storage bucket using the Cloud Run API.
[private]
_cloud-insert:
    SERVICE_URL="$(gcloud run services describe "{{service}}" --region "{{region}}" --format='value(status.url)')" && \
    curl -X POST "$SERVICE_URL/insert"

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
