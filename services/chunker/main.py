"""RAG Chunker — Cloud Run service triggered by Pub/Sub push on GCS finalize events.

Reads uploaded documents from GCS, splits into 500-token chunks with 50-token
overlap using LangChain, embeds via Vertex AI text-embedding-004, and upserts
vectors to a Vertex AI Vector Search index via streaming update.
"""

from __future__ import annotations

import base64
import json
import os
import traceback
from typing import Any

import structlog
import uvicorn
from fastapi import FastAPI, Request, Response

from chunker import process_document

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

app = FastAPI(title="rag-chunker", docs_url=None, redoc_url=None)

PROJECT_ID = os.environ["PROJECT_ID"]
REGION = os.environ["REGION"]
BUCKET_NAME = os.environ["BUCKET_NAME"]
VECTOR_SEARCH_INDEX_ID = os.environ["VECTOR_SEARCH_INDEX_ID"]
VECTOR_SEARCH_INDEX_ENDPOINT_ID = os.environ["VECTOR_SEARCH_INDEX_ENDPOINT_ID"]


@app.get("/health")
async def health() -> dict[str, str]:
    """Liveness check."""
    return {"status": "ok"}


@app.post("/")
async def handle_pubsub(request: Request) -> Response:
    """Handle Pub/Sub push messages containing GCS finalize events."""
    body = await request.json()

    message = body.get("message", {})
    if not message:
        logger.warning("pubsub_empty_message")
        return Response(status_code=204)

    # Decode the Pub/Sub message data (base64-encoded GCS notification)
    data_raw = message.get("data", "")
    try:
        data: dict[str, Any] = json.loads(base64.b64decode(data_raw))
    except (json.JSONDecodeError, ValueError):
        logger.error("pubsub_decode_error", raw=data_raw[:200])
        # Return 204 so Pub/Sub does not retry a permanently bad message
        return Response(status_code=204)

    bucket = data.get("bucket", "")
    object_name = data.get("name", "")
    content_type = data.get("contentType", "")

    if not bucket or not object_name:
        logger.warning("pubsub_missing_fields", data=data)
        return Response(status_code=204)

    log = logger.bind(
        service="rag-chunker",
        bucket=bucket,
        object_name=object_name,
        content_type=content_type,
    )

    # Skip non-document files (directories, partial uploads, etc.)
    supported_types = {
        "text/plain",
        "application/pdf",
        "text/markdown",
        "text/csv",
        "application/json",
        "application/epub+zip",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    }
    if content_type not in supported_types:
        log.info("skipping_unsupported_content_type")
        return Response(status_code=204)

    try:
        result = process_document(
            project_id=PROJECT_ID,
            region=REGION,
            bucket_name=bucket,
            object_name=object_name,
            index_id=VECTOR_SEARCH_INDEX_ID,
            index_endpoint_id=VECTOR_SEARCH_INDEX_ENDPOINT_ID,
            content_type=content_type,
        )
        log.info(
            "document_processed",
            chunk_count=result["chunk_count"],
            embed_latency_ms=result["embed_latency_ms"],
            upsert_latency_ms=result["upsert_latency_ms"],
            total_latency_ms=result["total_latency_ms"],
        )
    except Exception:
        log.error("document_processing_failed", exception=traceback.format_exc())
        # Return 500 so Pub/Sub retries
        return Response(status_code=500)

    return Response(status_code=200)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
