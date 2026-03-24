"""Core chunking, embedding, and upsert logic for the RAG ingestion pipeline."""

from __future__ import annotations

import hashlib
import tempfile
import time
from typing import Any

import structlog
from google.cloud import aiplatform, storage
from google.cloud.aiplatform.matching_engine import MatchingEngineIndex
from langchain_text_splitters import RecursiveCharacterTextSplitter
from vertexai.language_models import TextEmbeddingInput, TextEmbeddingModel

logger = structlog.get_logger()

# text-embedding-004 uses tiktoken cl100k_base tokenizer
CHUNK_SIZE = 500       # tokens
CHUNK_OVERLAP = 50     # tokens
EMBEDDING_MODEL = "text-embedding-004"
EMBEDDING_DIMENSIONS = 768
EMBEDDING_BATCH_SIZE = 250  # API limit per request


def process_document(
    *,
    project_id: str,
    region: str,
    bucket_name: str,
    object_name: str,
    index_id: str,
    index_endpoint_id: str,
) -> dict[str, Any]:
    """Download a document from GCS, chunk it, embed chunks, and upsert to Vector Search.

    Args:
        project_id: GCP project ID.
        region: GCP region.
        bucket_name: Source GCS bucket name.
        object_name: GCS object key.
        index_id: Vertex AI Vector Search index ID.
        index_endpoint_id: Vertex AI Vector Search index endpoint ID.

    Returns:
        Dict with chunk_count, embed_latency_ms, upsert_latency_ms, total_latency_ms.
    """
    t_start = time.monotonic()

    aiplatform.init(project=project_id, location=region)

    # ── Download from GCS ───────────────────────────────────────────────
    text = _download_document(bucket_name, object_name)

    # ── Chunk ───────────────────────────────────────────────────────────
    chunks = _split_text(text)
    if not chunks:
        logger.info("no_chunks_produced", object_name=object_name)
        elapsed = int((time.monotonic() - t_start) * 1000)
        return {
            "chunk_count": 0,
            "embed_latency_ms": 0,
            "upsert_latency_ms": 0,
            "total_latency_ms": elapsed,
        }

    # ── Embed ───────────────────────────────────────────────────────────
    t_embed = time.monotonic()
    embeddings = _embed_chunks(chunks)
    embed_latency_ms = int((time.monotonic() - t_embed) * 1000)

    # ── Upsert to Vector Search ─────────────────────────────────────────
    t_upsert = time.monotonic()
    datapoints = _build_datapoints(object_name, chunks, embeddings)
    _upsert_vectors(index_id, datapoints)
    upsert_latency_ms = int((time.monotonic() - t_upsert) * 1000)

    total_latency_ms = int((time.monotonic() - t_start) * 1000)

    return {
        "chunk_count": len(chunks),
        "embed_latency_ms": embed_latency_ms,
        "upsert_latency_ms": upsert_latency_ms,
        "total_latency_ms": total_latency_ms,
    }


def _download_document(bucket_name: str, object_name: str) -> str:
    """Download a GCS object and return its text content."""
    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(object_name)

    with tempfile.NamedTemporaryFile(suffix=".tmp") as tmp:
        blob.download_to_filename(tmp.name)
        with open(tmp.name, "r", encoding="utf-8", errors="replace") as f:
            return f.read()


def _split_text(text: str) -> list[str]:
    """Split text into chunks of ~500 tokens with 50-token overlap."""
    splitter = RecursiveCharacterTextSplitter.from_tiktoken_encoder(
        encoding_name="cl100k_base",
        chunk_size=CHUNK_SIZE,
        chunk_overlap=CHUNK_OVERLAP,
    )
    return splitter.split_text(text)


def _embed_chunks(chunks: list[str]) -> list[list[float]]:
    """Embed text chunks using Vertex AI text-embedding-004.

    Batches requests to stay within API limits.
    """
    model = TextEmbeddingModel.from_pretrained(EMBEDDING_MODEL)
    all_embeddings: list[list[float]] = []

    for i in range(0, len(chunks), EMBEDDING_BATCH_SIZE):
        batch = chunks[i : i + EMBEDDING_BATCH_SIZE]
        inputs = [
            TextEmbeddingInput(text=chunk, task_type="RETRIEVAL_DOCUMENT")
            for chunk in batch
        ]
        results = model.get_embeddings(
            inputs,
            output_dimensionality=EMBEDDING_DIMENSIONS,
        )
        all_embeddings.extend([e.values for e in results])

    return all_embeddings


def _build_datapoints(
    object_name: str,
    chunks: list[str],
    embeddings: list[list[float]],
) -> list[dict[str, Any]]:
    """Build Vector Search datapoints with deterministic IDs.

    Each datapoint ID is a hash of the source object name and chunk index,
    ensuring idempotent upserts on re-processing.
    """
    datapoints = []
    for i, (chunk, embedding) in enumerate(zip(chunks, embeddings)):
        raw_id = f"{object_name}::chunk_{i}"
        datapoint_id = hashlib.sha256(raw_id.encode()).hexdigest()[:40]
        datapoints.append(
            {
                "datapoint_id": datapoint_id,
                "feature_vector": embedding,
                "restricts": [
                    {"namespace": "source", "allow_list": [object_name]},
                ],
            }
        )
    return datapoints


def _upsert_vectors(
    index_id: str,
    datapoints: list[dict[str, Any]],
) -> None:
    """Upsert datapoints to the Vertex AI Vector Search index via streaming update."""
    index = MatchingEngineIndex(index_name=index_id)
    index.upsert_datapoints(datapoints=datapoints)
