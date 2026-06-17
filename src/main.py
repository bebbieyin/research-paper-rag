"""FastAPI application for the research paper RAG pipeline."""

import logging

from fastapi import FastAPI, HTTPException, status
from starlette.concurrency import run_in_threadpool

from src.rag import answer_question as run_rag
from src.schema import HealthCheck, QuestionAnswer, QuestionRequest

logger = logging.getLogger(__name__)

app = FastAPI(title="Research Paper RAG API", version="0.1.0")


@app.get("/health")
def health() -> HealthCheck:
    """Return API health without initializing external RAG dependencies."""
    return HealthCheck(status="ok")


@app.post("/ask")
async def ask(request: QuestionRequest) -> QuestionAnswer:
    """Answer a question using the indexed research papers."""
    try:
        return await run_in_threadpool(run_rag, request.question)
    except Exception as exc:
        logger.exception("RAG service is unavailable.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="RAG service is unavailable.",
        ) from exc
