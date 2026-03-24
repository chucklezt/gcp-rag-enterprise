import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "RAG Query Interface",
  description: "Enterprise RAG system powered by Vertex AI and Gemini",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="font-sans antialiased">{children}</body>
    </html>
  );
}
