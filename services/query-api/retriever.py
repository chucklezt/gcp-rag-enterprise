"""Embedding and Vector Search retrieval logic."""

from __future__ import annotations

import os
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any

import structlog
from google.cloud import firestore
from google.cloud.aiplatform.matching_engine import MatchingEngineIndexEndpoint
from vertexai.language_models import TextEmbeddingInput, TextEmbeddingModel

logger = structlog.get_logger()

EMBEDDING_MODEL = "text-embedding-004"
EMBEDDING_DIMENSIONS = 768
TOP_K = 5


def embed_query(question: str) -> tuple[list[float], int]:
    """Embed a query string using text-embedding-004.

    Args:
        question: The user's question.

    Returns:
        Tuple of (embedding vector, latency in ms).
    """
    model = TextEmbeddingModel.from_pretrained(EMBEDDING_MODEL)

    t_start = time.monotonic()
    inputs = [TextEmbeddingInput(text=question, task_type="RETRIEVAL_QUERY")]
    results = model.get_embeddings(inputs, output_dimensionality=EMBEDDING_DIMENSIONS)
    latency_ms = int((time.monotonic() - t_start) * 1000)

    return results[0].values, latency_ms


def retrieve_chunks(
    index_endpoint_id: str,
    deployed_index_id: str,
    embedding: list[float],
) -> tuple[list[dict[str, Any]], int]:
    """Query Vertex AI Vector Search via the private VPC-peered endpoint.

    Uses the match() method which connects over the private gRPC stub
    to the VPC-peered index endpoint.

    Args:
        index_endpoint_id: Full resource name of the index endpoint.
        deployed_index_id: ID of the deployed index on the endpoint.
        embedding: Query embedding vector.

    Returns:
        Tuple of (list of match dicts with id and distance, latency in ms).
    """
    endpoint = MatchingEngineIndexEndpoint(index_endpoint_name=index_endpoint_id)

    t_start = time.monotonic()
    response = endpoint.match(
        deployed_index_id=deployed_index_id,
        queries=[embedding],
        num_neighbors=TOP_K,
    )
    latency_ms = int((time.monotonic() - t_start) * 1000)

    logger.debug(
        "vector_search_raw_response",
        service="rag-query-api",
        deployed_index_id=deployed_index_id,
        num_queries=len(response),
        num_neighbors=len(response[0]) if response else 0,
        matches=[
            {"id": n.id, "distance": n.distance} for n in response[0]
        ] if response else [],
    )

    matches = []
    for neighbor in response[0]:
        matches.append(
            {
                "id": neighbor.id,
                "distance": neighbor.distance,
            }
        )

    # Fetch chunk text and metadata from Firestore in parallel
    project_id = os.environ.get("PROJECT_ID", "")
    if project_id and matches:
        chunk_docs = _fetch_chunk_docs(project_id, [m["id"] for m in matches])
        for match in matches:
            doc_data = chunk_docs.get(match["id"], {})
            match["content"] = doc_data.get("text", "")
            match["book_title"] = doc_data.get("book_title", "")
            match["chapter_title"] = doc_data.get("chapter_title", "")
            match["chapter_index"] = doc_data.get("chapter_index", "")

    return matches, latency_ms


def _fetch_chunk_docs(
    project_id: str,
    datapoint_ids: list[str],
) -> dict[str, dict[str, Any]]:
    """Fetch chunk documents from Firestore for the given datapoint IDs.

    Args:
        project_id: GCP project ID.
        datapoint_ids: List of Vector Search datapoint IDs (Firestore doc IDs).

    Returns:
        Dict mapping datapoint ID to the full Firestore document fields.
    """
    db = firestore.Client(project=project_id, database="rag-chunks")

    def _get_doc(doc_id: str) -> tuple[str, dict[str, Any]]:
        doc = db.collection("chunks").document(doc_id).get()
        if doc.exists:
            return doc_id, doc.to_dict()
        return doc_id, {}

    with ThreadPoolExecutor(max_workers=len(datapoint_ids)) as executor:
        results = executor.map(_get_doc, datapoint_ids)

    return dict(results)
