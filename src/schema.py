"""Pydantic schemas for the RAG API."""

from pydantic import BaseModel, Field


class HealthCheck(BaseModel):
    """Health check response."""

    status: str


class InsertResponse(BaseModel):
    """Response returned after inserting PDF chunks."""

    loaded_pages: int
    indexed_chunks: int
    namespace: str


class QuestionRequest(BaseModel):
    """Input schema for a user question."""

    question: str = Field(min_length=1, description="Question to answer.")


class SourceCitation(BaseModel):
    """Citation for one retrieved source chunk."""

    source: str = Field(description="PDF file name.")
    page: int | str = Field(description="Page number, when available.")
    chunk_number: int | str = Field(description="Chunk number, when available.")
    quote: str = Field(description="Short supporting quote from the source chunk.")


class QuestionAnswer(BaseModel):
    """Grounded answer returned by the RAG pipeline."""

    question: str
    answer: str
    sources: list[SourceCitation] = Field(default_factory=list)
    confidence: str = Field(description="One of: high, medium, low.")
