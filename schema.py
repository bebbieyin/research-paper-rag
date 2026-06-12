"""Pydantic schemas for the RAG API."""

from langchain_core.pydantic_v1 import BaseModel, Field


class QuestionData(BaseModel):
    """Input schema for a user question."""

    question: str


class QuestionAnswer(BaseModel):
    """Output schema for a question and its answer."""

    question: str = Field(description="question asked by user")
    answer: str = Field(description="answer from model")
