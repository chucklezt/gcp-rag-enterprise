"use client";

import { useState } from "react";
import type { QueryMetadata } from "@/lib/sse";

interface MetadataPanelProps {
  metadata: QueryMetadata;
}

export function MetadataPanel({ metadata }: MetadataPanelProps) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="ml-0 mt-2">
      <button
        onClick={() => setExpanded(!expanded)}
        className="text-xs text-muted hover:text-accent-light transition-colors flex items-center gap-1"
      >
        <span className={`transition-transform ${expanded ? "rotate-90" : ""}`}>
          &#9654;
        </span>
        {metadata.total_latency_ms}ms &middot; {metadata.chunk_count} chunks &middot;{" "}
        {metadata.output_tokens} tokens
      </button>

      {expanded && (
        <div className="mt-2 bg-panel border border-muted/20 rounded-lg p-3 text-xs text-muted grid grid-cols-2 gap-y-1.5 gap-x-6 max-w-sm">
          <span>Query ID</span>
          <span className="text-text font-mono">{metadata.query_id}</span>
          <span>Embed</span>
          <span className="text-text">{metadata.embed_latency_ms}ms</span>
          <span>Retrieve</span>
          <span className="text-text">{metadata.retrieve_latency_ms}ms</span>
          <span>Generate</span>
          <span className="text-text">{metadata.generate_latency_ms}ms</span>
          <span>Total</span>
          <span className="text-text">{metadata.total_latency_ms}ms</span>
          <span>Chunks</span>
          <span className="text-text">{metadata.chunk_count}</span>
          <span>Input tokens</span>
          <span className="text-text">{metadata.input_tokens}</span>
          <span>Output tokens</span>
          <span className="text-text">{metadata.output_tokens}</span>
        </div>
      )}
    </div>
  );
}
