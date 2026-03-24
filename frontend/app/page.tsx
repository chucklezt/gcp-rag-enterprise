import { Chat } from "@/components/chat";

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center bg-bg">
      <div className="w-full max-w-3xl flex flex-col h-screen">
        <header className="flex items-center gap-3 px-6 py-4 border-b border-panel">
          <div className="h-8 w-8 rounded-lg bg-accent flex items-center justify-center">
            <span className="text-white text-sm font-semibold">R</span>
          </div>
          <div>
            <h1 className="text-lg font-semibold text-text">RAG Query Interface</h1>
            <p className="text-xs text-muted">Vertex AI Vector Search + Gemini 2.5 Flash</p>
          </div>
        </header>
        <Chat />
      </div>
    </main>
  );
}
