/**
 * SSE client for streaming RAG query responses.
 * Connects to the query API and yields parsed events.
 */

const QUERY_API_URL =
  process.env.NEXT_PUBLIC_QUERY_API_URL ??
  "https://rag-query-api-204300710565.us-central1.run.app/query";

export interface QueryMetadata {
  query_id: string;
  chunk_count: number;
  embed_latency_ms: number;
  retrieve_latency_ms: number;
  generate_latency_ms: number;
  total_latency_ms: number;
  input_tokens: number;
  output_tokens: number;
}

export type SSEEvent =
  | { type: "token"; data: string }
  | { type: "metadata"; data: QueryMetadata }
  | { type: "done" }
  | { type: "error"; data: string };

export async function* streamQuery(
  question: string,
  signal?: AbortSignal
): AsyncGenerator<SSEEvent> {
  const response = await fetch(QUERY_API_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ question }),
    signal,
  });

  if (!response.ok) {
    yield { type: "error", data: `API error: ${response.status}` };
    return;
  }

  const reader = response.body?.getReader();
  if (!reader) {
    yield { type: "error", data: "No response body" };
    return;
  }

  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split("\n");
    // Keep the last partial line in the buffer
    buffer = lines.pop() ?? "";

    let currentEvent = "";

    for (const line of lines) {
      if (line.startsWith("event: ")) {
        currentEvent = line.slice(7).trim();
      } else if (line.startsWith("data: ")) {
        const data = line.slice(6);

        if (currentEvent === "token") {
          yield { type: "token", data };
        } else if (currentEvent === "metadata") {
          try {
            yield { type: "metadata", data: JSON.parse(data) };
          } catch {
            yield { type: "error", data: "Failed to parse metadata" };
          }
        } else if (currentEvent === "done") {
          yield { type: "done" };
        }

        currentEvent = "";
      }
    }
  }
}
