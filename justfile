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

alias build := docker-build
alias start := docker-start
alias stop := docker-stop
alias logs := docker-logs
alias health := api-health
alias insert := api-insert
alias ask := api-ask
alias deploy := deploy-production

# Show the main workflow commands.
default:
    @echo "Main workflow:"
    @echo "  just deploy-local        # rebuild and run the app locally with Docker"
    @echo "  just deploy-production   # build, push, and deploy to Cloud Run"
    @echo ""
    @echo "Useful checks:"
    @echo "  just health              # call local /health"
    @echo "  just ask \"question\"      # call local /ask"
    @echo "  just logs                # follow local Docker logs"
    @echo "  just stop                # stop local Docker app"
    @echo ""
    @echo "All commands:"
    @just --list --unsorted

# Rebuild and run the app locally with Docker after code changes.
deploy-local:
    docker compose up --build -d
    @echo "Local API: {{local_url}}"

# Build, push, and deploy the app to Cloud Run.
deploy-production: cloud-release

# Run the API locally without Docker.
local-run:
    uv run uvicorn src.main:app --reload --port {{port}}

# Run local tests.
local-test:
    uv run pytest

# Call the local health endpoint.
api-health:
    curl {{local_url}}/health

# Index PDFs from the local or Docker-mounted data directory.
api-insert:
    curl -X POST {{local_url}}/insert

# Ask a question against the local API.
api-ask question:
    curl -X POST {{local_url}}/ask \
      -H "Content-Type: application/json" \
      -d '{"question":"{{question}}"}'

# Build the local Docker image used by Compose.
docker-build:
    docker compose build

# Rebuild the local Docker image without cache.
docker-rebuild:
    docker compose build --no-cache

# Start the Dockerized API in the foreground.
docker-up:
    docker compose up

# Start the Dockerized API in the background.
docker-start:
    docker compose up -d

# Stop the Dockerized API.
docker-stop:
    docker compose down

# Restart the Dockerized API in the background.
docker-restart:
    docker compose down
    docker compose up -d

# Show running Compose services.
docker-ps:
    docker compose ps

# Follow API logs from Docker Compose.
docker-logs:
    docker compose logs -f api

# Show the GCP Artifact Registry image name used for deploys.
cloud-image:
    @echo "{{image}}"

# Build the image for GCP Artifact Registry. Set PROJECT_ID in .env first.
cloud-build:
    docker build --platform linux/amd64 -t "{{image}}" .

# Push the image to GCP Artifact Registry. Set PROJECT_ID in .env first.
cloud-push:
    docker push "{{image}}"

# Grant Cloud Run's runtime service account access to Secret Manager secrets.
cloud-grant-secret-access:
    PROJECT_NUMBER="$(gcloud projects describe "{{project_id}}" --format='value(projectNumber)')" && \
    RUNTIME_SERVICE_ACCOUNT="$PROJECT_NUMBER-compute@developer.gserviceaccount.com" && \
    gcloud secrets add-iam-policy-binding pinecone-api-key \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role="roles/secretmanager.secretAccessor" && \
    gcloud secrets add-iam-policy-binding huggingfacehub-api-token \
      --member="serviceAccount:$RUNTIME_SERVICE_ACCOUNT" \
      --role="roles/secretmanager.secretAccessor"

# Deploy the latest pushed image to Cloud Run. Set PROJECT_ID in .env first.
cloud-deploy:
    gcloud run deploy "{{service}}" \
      --image "{{image}}" \
      --region "{{region}}" \
      --allow-unauthenticated \
      --port 8000 \
      --memory "{{cloud_run_memory}}" \
      --cpu "{{cloud_run_cpu}}" \
      --min-instances 0 \
      --max-instances 2 \
      --set-env-vars DATA_DIR="{{cloud_run_data_dir}}",PINECONE_INDEX_NAME="{{pinecone_index_name}}",PINECONE_NAMESPACE="{{pinecone_namespace}}",HF_EMBEDDING_MODEL="{{hf_embedding_model}}",HF_EMBEDDING_DIMENSION="{{hf_embedding_dimension}}",HF_CHAT_MODEL="{{hf_chat_model}}",HF_PROVIDER="{{hf_provider}}",PINECONE_RERANK_MODEL="{{pinecone_rerank_model}}",CHUNK_SIZE="{{chunk_size}}",CHUNK_OVERLAP="{{chunk_overlap}}",RETRIEVAL_TOP_K="{{retrieval_top_k}}",RERANK_TOP_N="{{rerank_top_n}}" \
      --set-secrets PINECONE_API_KEY=pinecone-api-key:latest,HUGGINGFACEHUB_API_TOKEN=huggingfacehub-api-token:latest,HF_TOKEN=huggingfacehub-api-token:latest

# Build, push, and deploy to Cloud Run.
cloud-release: cloud-build cloud-push cloud-deploy

# Print the deployed Cloud Run service URL.
cloud-url:
    gcloud run services describe "{{service}}" --region "{{region}}" --format='value(status.url)'

# Show recent Cloud Run logs for this service.
cloud-logs:
    gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="{{service}}"' \
      --project "{{project_id}}" \
      --limit 50 \
      --format "value(timestamp,severity,textPayload)"
