"use client";

import { useState, useCallback, useRef } from "react";

// Запросы идут через наш API route (/api/chat), чтобы обойти CORS Algolia и не светить ключ в браузере.
function getChatApiUrl() {
  if (typeof window !== "undefined") return "/api/chat";
  const base = process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : "http://localhost:3000";
  return `${base}/api/chat`;
}

type Message = { role: "user" | "assistant"; content: string };

function useAlgoliaChat() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [streamingContent, setStreamingContent] = useState("");
  const [status, setStatus] = useState<"ready" | "streaming" | "error">("ready");
  const [error, setError] = useState<string | null>(null);
  const rafRef = useRef<number | null>(null);
  const pendingAcc = useRef("");

  const sendMessage = useCallback(async (text: string) => {
    if (!text.trim()) return;
    setError(null);
    setMessages((prev) => [...prev, { role: "user", content: text.trim() }]);
    setStreamingContent("");
    setStatus("streaming");

    try {
      const res = await fetch(getChatApiUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          messages: [{ role: "user", parts: [{ text: text.trim() }] }],
        }),
      });

      if (!res.ok) {
        const body = await res.text();
        let errMsg = body;
        try {
          const j = JSON.parse(body);
          errMsg = j.error ?? j.message ?? j.detail ?? body;
        } catch {
          if (body.startsWith("<!")) errMsg = "Algolia вернул HTML (возможно Cloudflare).";
        }
        throw new Error(errMsg);
      }

      const reader = res.body?.getReader();
      const decoder = new TextDecoder();
      let acc = "";
      let buf = "";

      if (reader) {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const lines = buf.split("\n");
          buf = lines.pop() ?? "";
          for (const line of lines) {
            if (line.startsWith("data: ")) {
              try {
                const obj = JSON.parse(line.slice(6).trim());
                if (obj.type === "text-delta" && typeof obj.delta === "string") {
                  acc += obj.delta;
                  pendingAcc.current = acc;
                  // Обновляем UI не чаще раза за кадр — меньше нагрузка на React при частых дельтах
                  if (rafRef.current === null) {
                    rafRef.current = requestAnimationFrame(() => {
                      rafRef.current = null;
                      setStreamingContent(pendingAcc.current);
                    });
                  }
                }
                if (obj.error) {
                  setError(String(obj.error));
                  setStatus("error");
                  return;
                }
              } catch {
                // skip non-JSON lines
              }
            }
          }
        }
      }

      if (rafRef.current !== null) {
        cancelAnimationFrame(rafRef.current);
        rafRef.current = null;
      }
      setMessages((prev) => [...prev, { role: "assistant", content: acc }]);
      setStreamingContent("");
      setStatus("ready");
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setStatus("error");
      setStreamingContent("");
    }
  }, []);

  return { messages, streamingContent, status, error, sendMessage };
}

export default function ChatPage() {
  const { messages, streamingContent, status, error, sendMessage } = useAlgoliaChat();

  return (
    <div className="chat-layout">
      <header className="chat-header">
        <h1>Kinescope — база знаний</h1>
        <p className="chat-subtitle">Чат с ассистентом (Algolia Agent)</p>
      </header>

      <main className="chat-main">
        <div className="chat-messages">
          {messages.length === 0 && !streamingContent && (
            <div className="chat-welcome">
              <p>Задайте вопрос по документации Kinescope.</p>
              <p className="chat-hint">Например: «Как загрузить видео?»</p>
            </div>
          )}
          {messages.map((msg, i) => (
            <div key={i} className={`chat-message chat-message--${msg.role}`}>
              <span className="chat-message-role">{msg.role === "user" ? "Вы" : "Ассистент"}</span>
              <div className="chat-message-content">{msg.content}</div>
            </div>
          ))}
          {streamingContent && (
            <div className="chat-message chat-message--assistant">
              <span className="chat-message-role">Ассистент</span>
              <div className="chat-message-content">{streamingContent}</div>
            </div>
          )}
          {error && (
            <div className="chat-message chat-message--assistant chat-message--error">
              <span className="chat-message-role">Ошибка</span>
              <div className="chat-message-content">{error}</div>
            </div>
          )}
        </div>

        <form
          className="chat-form"
          onSubmit={(e) => {
            e.preventDefault();
            const form = e.currentTarget;
            const textarea = form.querySelector("textarea");
            const text = textarea?.value?.trim();
            if (text) {
              sendMessage(text);
              textarea!.value = "";
            }
          }}
        >
          <textarea
            placeholder="Спросите что угодно..."
            rows={1}
            disabled={status === "streaming"}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                e.currentTarget.form?.requestSubmit();
              }
            }}
          />
          <button type="submit" disabled={status === "streaming"}>
            Отправить
          </button>
        </form>
      </main>
    </div>
  );
}
