"""Embedding and Vector Search retrieval logic."""

from __future__ import annotations

import time
from typing import Any

import structlog
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

    matches = []
    for neighbor in response[0]:
        matches.append(
            {
                "id": neighbor.id,
                "distance": neighbor.distance,
            }
        )

    return matches, latency_ms
