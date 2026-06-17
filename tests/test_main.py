"""Tests for the FastAPI application."""

from __future__ import annotations

from fastapi.testclient import TestClient

from src.main import app


def test_health_returns_ok() -> None:
    """Health endpoint returns a successful status."""
    client = TestClient(app)

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
