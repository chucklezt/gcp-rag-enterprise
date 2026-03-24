"use client";

import { useCallback, useRef, useState } from "react";
import { type QueryMetadata, type SSEEvent, streamQuery } from "@/lib/sse";
import { ChatMessage } from "@/components/chat-message";
import { MetadataPanel } from "@/components/metadata-panel";

interface Message {
  role: "user" | "assistant";
  content: string;
  metadata?: QueryMetadata;
}

export function Chat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState("");
  const [isStreaming, setIsStreaming] = useState(false);
  const abortRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      scrollRef.current?.scrollTo({
        top: scrollRef.current.scrollHeight,
        behavior: "smooth",
      });
    });
  }, []);

  const handleSubmit = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      const question = input.trim();
      if (!question || isStreaming) return;

      setInput("");
      setIsStreaming(true);

      const userMsg: Message = { role: "user", content: question };
      const assistantMsg: Message = { role: "assistant", content: "" };

      setMessages((prev) => [...prev, userMsg, assistantMsg]);
      scrollToBottom();

      const controller = new AbortController();
      abortRef.current = controller;

      try {
        for await (const event of streamQuery(question, controller.signal)) {
          if (event.type === "token") {
            setMessages((prev) => {
              const updated = [...prev];
              const last = updated[updated.length - 1];
              updated[updated.length - 1] = {
                ...last,
                content: last.content + event.data,
              };
              return updated;
            });
            scrollToBottom();
          } else if (event.type === "metadata") {
            setMessages((prev) => {
              const updated = [...prev];
              updated[updated.length - 1] = {
                ...updated[updated.length - 1],
                metadata: event.data,
              };
              return updated;
            });
          } else if (event.type === "error") {
            setMessages((prev) => {
              const updated = [...prev];
              updated[updated.length - 1] = {
                ...updated[updated.length - 1],
                content: `Error: ${event.data}`,
              };
              return updated;
            });
          }
        }
      } catch (err) {
        if ((err as Error).name !== "AbortError") {
          setMessages((prev) => {
            const updated = [...prev];
            updated[updated.length - 1] = {
              ...updated[updated.length - 1],
              content: "Connection error. Please try again.",
            };
            return updated;
          });
        }
      } finally {
        setIsStreaming(false);
        abortRef.current = null;
      }
    },
    [input, isStreaming, scrollToBottom]
  );

  const handleStop = useCallback(() => {
    abortRef.current?.abort();
    setIsStreaming(false);
  }, []);

  return (
    <>
      {/* Messages area */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
        {messages.length === 0 && (
          <div className="flex flex-col items-center justify-center h-full text-center">
            <div className="h-16 w-16 rounded-2xl bg-accent/20 flex items-center justify-center mb-4">
              <span className="text-accent-light text-2xl font-semibold">?</span>
            </div>
            <p className="text-text text-lg font-medium mb-1">Ask a question</p>
            <p className="text-muted text-sm max-w-md">
              Your documents are indexed and ready. Ask anything about them
              and get answers powered by Gemini 2.5 Flash.
            </p>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i}>
            <ChatMessage role={msg.role} content={msg.content} />
            {msg.metadata && <MetadataPanel metadata={msg.metadata} />}
          </div>
        ))}
      </div>

      {/* Input area */}
      <div className="border-t border-panel px-6 py-4">
        <form onSubmit={handleSubmit} className="flex gap-3">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Ask a question about your documents..."
            disabled={isStreaming}
            className="flex-1 bg-panel border border-muted/30 rounded-lg px-4 py-3 text-text
                       placeholder:text-muted focus:outline-none focus:border-accent
                       transition-colors disabled:opacity-50"
          />
          {isStreaming ? (
            <button
              type="button"
              onClick={handleStop}
              className="px-5 py-3 rounded-lg bg-red-600/80 text-white font-medium
                         hover:bg-red-600 transition-colors"
            >
              Stop
            </button>
          ) : (
            <button
              type="submit"
              disabled={!input.trim()}
              className="px-5 py-3 rounded-lg bg-accent text-white font-medium
                         hover:bg-accent-light transition-colors
                         disabled:opacity-40 disabled:cursor-not-allowed"
            >
              Send
            </button>
          )}
        </form>
      </div>
    </>
  );
}
