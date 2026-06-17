"""Test configuration helpers."""

from __future__ import annotations

import os

REQUIRED_RAG_ENV = {
    "PINECONE_INDEX_NAME": "test-index",
    "PINECONE_NAMESPACE": "test-namespace",
    "HF_EMBEDDING_MODEL": "test-embedding-model",
    "HF_EMBEDDING_DIMENSION": "384",
    "HF_CHAT_MODEL": "test-chat-model",
    "HF_PROVIDER": "test-provider",
    "PINECONE_RERANK_MODEL": "test-rerank-model",
    "CHUNK_SIZE": "1000",
    "CHUNK_OVERLAP": "100",
    "RETRIEVAL_TOP_K": "4",
    "RERANK_TOP_N": "2",
}


def pytest_configure() -> None:
    """Provide config required when importing the API app."""
    for env_name, env_value in REQUIRED_RAG_ENV.items():
        os.environ.setdefault(env_name, env_value)
