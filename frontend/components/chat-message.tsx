"use client";

interface ChatMessageProps {
  role: "user" | "assistant";
  content: string;
}

export function ChatMessage({ role, content }: ChatMessageProps) {
  const isUser = role === "user";

  return (
    <div className={`flex ${isUser ? "justify-end" : "justify-start"}`}>
      <div
        className={`max-w-[85%] rounded-xl px-4 py-3 text-sm leading-relaxed whitespace-pre-wrap ${
          isUser
            ? "bg-accent text-white"
            : "bg-panel border border-muted/20 text-text"
        }`}
      >
        {content || (
          <span className="inline-flex gap-1">
            <span className="h-2 w-2 rounded-full bg-accent-light animate-pulse" />
            <span className="h-2 w-2 rounded-full bg-accent-light animate-pulse [animation-delay:150ms]" />
            <span className="h-2 w-2 rounded-full bg-accent-light animate-pulse [animation-delay:300ms]" />
          </span>
        )}
      </div>
    </div>
  );
}
