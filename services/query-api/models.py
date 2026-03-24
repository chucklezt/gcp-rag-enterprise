"""Pydantic v2 request/response models for the RAG query API."""

from __future__ import annotations

from pydantic import BaseModel, Field


class QueryRequest(BaseModel):
    """Incoming question from the frontend."""

    question: str = Field(..., min_length=1, max_length=2000)


class QueryMetadata(BaseModel):
    """Metadata returned in the final SSE event."""

    query_id: str
    chunk_count: int
    embed_latency_ms: int
    retrieve_latency_ms: int
    generate_latency_ms: int
    total_latency_ms: int
    input_tokens: int
    output_tokens: int
