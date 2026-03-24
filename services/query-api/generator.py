"""Gemini 2.5 Flash streaming generation logic."""

from __future__ import annotations

import time
from collections.abc import Generator
from typing import Any

import structlog
from vertexai.generative_models import GenerativeModel

logger = structlog.get_logger()

MODEL_ID = "gemini-2.5-flash"

SYSTEM_INSTRUCTION = (
    "You are a helpful assistant that answers questions based on the provided context. "
    "Use only the information from the context chunks to answer. "
    "If the context does not contain enough information to answer, say so clearly. "
    "Cite which chunk(s) support your answer when possible."
)


def build_prompt(question: str, chunks: list[dict[str, Any]]) -> str:
    """Build the RAG prompt with retrieved context chunks.

    Args:
        question: The user's question.
        chunks: List of chunk dicts with 'id' and optionally 'content'.

    Returns:
        Formatted prompt string.
    """
    context_parts = []
    for i, chunk in enumerate(chunks, 1):
        content = chunk.get("content", f"[Chunk ID: {chunk['id']}]")
        context_parts.append(f"[Chunk {i}] (ID: {chunk['id']})\n{content}")

    context_block = "\n\n".join(context_parts)

    return (
        f"Context:\n{context_block}\n\n"
        f"Question: {question}\n\n"
        f"Answer based on the context above:"
    )


def stream_generate(
    prompt: str,
) -> Generator[dict[str, Any], None, None]:
    """Stream tokens from Gemini 2.5 Flash and yield SSE-ready dicts.

    Yields dicts with either:
        {"type": "token", "data": "..."} for each streamed token
        {"type": "done", "input_tokens": N, "output_tokens": N, "latency_ms": N}
            as the final event

    Args:
        prompt: The full RAG prompt to send to the model.
    """
    model = GenerativeModel(
        model_name=MODEL_ID,
        system_instruction=SYSTEM_INSTRUCTION,
    )

    t_start = time.monotonic()
    input_tokens = 0
    output_tokens = 0

    response = model.generate_content(
        prompt,
        stream=True,
    )

    for chunk in response:
        if chunk.text:
            yield {"type": "token", "data": chunk.text}

        # Accumulate usage metadata when available
        if hasattr(chunk, "usage_metadata") and chunk.usage_metadata:
            meta = chunk.usage_metadata
            if hasattr(meta, "prompt_token_count") and meta.prompt_token_count:
                input_tokens = meta.prompt_token_count
            if hasattr(meta, "candidates_token_count") and meta.candidates_token_count:
                output_tokens = meta.candidates_token_count

    latency_ms = int((time.monotonic() - t_start) * 1000)

    yield {
        "type": "done",
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "latency_ms": latency_ms,
    }
