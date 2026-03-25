"""RAG Query API — Cloud Run service serving retrieval-augmented generation.

Receives a question, embeds it with text-embedding-004, retrieves top-5 chunks
from Vertex AI Vector Search, generates a streaming response via Gemini 2.5 Flash,
and returns the result as Server-Sent Events.
"""

from __future__ import annotations

import json
import os
import uuid
from collections.abc import AsyncGenerator

import structlog
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import aiplatform
from sse_starlette.sse import EventSourceResponse

from generator import build_prompt, stream_generate
from models import QueryRequest
from retriever import embed_query, retrieve_chunks

structlog.configure(
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.make_filtering_bound_logger(0),
)

logger = structlog.get_logger()

app = FastAPI(title="rag-query-api", docs_url=None, redoc_url=None)

# TODO: Restrict allow_origins to the frontend URL before production use.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["*"],
)

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
VECTOR_SEARCH_INDEX_ID = os.environ["VECTOR_SEARCH_INDEX_ID"]
VECTOR_SEARCH_INDEX_ENDPOINT_ID = os.environ["VECTOR_SEARCH_INDEX_ENDPOINT_ID"]
DEPLOYED_INDEX_ID = os.environ.get("DEPLOYED_INDEX_ID", "rag_embeddings_deployed")


@app.on_event("startup")
async def startup() -> None:
    """Initialize Vertex AI SDK on startup."""
    aiplatform.init(project=PROJECT_ID, location=REGION)


@app.get("/health")
async def health() -> dict[str, str]:
    """Liveness check."""
    return {"status": "ok"}


@app.post("/query")
async def query(body: QueryRequest, request: Request) -> EventSourceResponse:
    """Handle a RAG query and stream the response as SSE."""
    query_id = uuid.uuid4().hex[:16]
    log = logger.bind(service="rag-query-api", query_id=query_id)

    async def event_stream() -> AsyncGenerator[dict[str, str], None]:
        import time

        t_total = time.monotonic()

        # ── Embed the question ──────────────────────────────────────
        embedding, embed_latency_ms = embed_query(body.question)

        # ── Retrieve top-5 chunks ───────────────────────────────────
        matches, retrieve_latency_ms = retrieve_chunks(
            index_endpoint_id=VECTOR_SEARCH_INDEX_ENDPOINT_ID,
            deployed_index_id=DEPLOYED_INDEX_ID,
            embedding=embedding,
        )

        chunk_count = len(matches)

        # ── Build prompt and stream from Gemini ─────────────────────
        prompt = build_prompt(body.question, matches)

        generate_latency_ms = 0
        input_tokens = 0
        output_tokens = 0

        for event in stream_generate(prompt):
            if event["type"] == "token":
                yield {"event": "token", "data": event["data"]}
            elif event["type"] == "done":
                generate_latency_ms = event["latency_ms"]
                input_tokens = event["input_tokens"]
                output_tokens = event["output_tokens"]

        total_latency_ms = int((time.monotonic() - t_total) * 1000)

        # ── Final metadata event ────────────────────────────────────
        metadata = {
            "query_id": query_id,
            "chunk_count": chunk_count,
            "embed_latency_ms": embed_latency_ms,
            "retrieve_latency_ms": retrieve_latency_ms,
            "generate_latency_ms": generate_latency_ms,
            "total_latency_ms": total_latency_ms,
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
        }
        yield {"event": "metadata", "data": json.dumps(metadata)}
        yield {"event": "done", "data": ""}

        # ── Structured log ──────────────────────────────────────────
        log.info(
            "query_completed",
            latency_ms=total_latency_ms,
            embed_latency_ms=embed_latency_ms,
            retrieve_latency_ms=retrieve_latency_ms,
            generate_latency_ms=generate_latency_ms,
            chunk_count=chunk_count,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
        )

    return EventSourceResponse(event_stream())


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
