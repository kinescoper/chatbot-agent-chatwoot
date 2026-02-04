import { NextRequest, NextResponse } from "next/server";

const APP_ID = process.env.ALGOLIA_APPLICATION_ID || process.env.NEXT_PUBLIC_ALGOLIA_APPLICATION_ID || "SRC8UTYBUO";
const API_KEY = process.env.ALGOLIA_API_KEY || process.env.NEXT_PUBLIC_ALGOLIA_API_KEY;
const AGENT_ID = process.env.ALGOLIA_AGENT_ID || process.env.NEXT_PUBLIC_ALGOLIA_AGENT_ID || "1feae05a-7e87-4508-88c8-2d7da88e30de";
// Региональный эндпоинт (например https://agent-studio.us.algolia.com) уменьшает RTT, если Vercel в США
const BASE_URL = process.env.ALGOLIA_AGENT_STUDIO_BASE_URL || `https://${APP_ID.toLowerCase()}.algolia.net/agent-studio`;
const ALGOLIA_URL = `${BASE_URL}/1/agents/${AGENT_ID}/completions?stream=true&compatibilityMode=ai-sdk-5`;

export async function POST(req: NextRequest) {
  if (!API_KEY) {
    return NextResponse.json(
      { error: "Algolia API key not configured. Set ALGOLIA_API_KEY or NEXT_PUBLIC_ALGOLIA_API_KEY in Vercel." },
      { status: 503 }
    );
  }

  let body: { messages?: Array<{ role: string; parts?: Array<{ text: string }> }> };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ error: "Body must contain messages array" }, { status: 400 });
  }

  const stream = new ReadableStream({
    async start(controller) {
      const encoder = new TextEncoder();
      try {
        const res = await fetch(ALGOLIA_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Accept: "text/event-stream",
            "x-algolia-application-id": APP_ID,
            "x-algolia-api-key": API_KEY,
          },
          body: JSON.stringify({ messages }),
        });

        if (!res.ok) {
          const text = await res.text();
          let errMsg = text;
          try {
            const j = JSON.parse(text);
            errMsg = j.message ?? j.detail ?? text;
          } catch {
            if (text.startsWith("<!")) errMsg = "Algolia returned HTML (e.g. Cloudflare).";
          }
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: errMsg })}\n\n`));
          controller.close();
          return;
        }

        const reader = res.body?.getReader();
        if (!reader) {
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: "No response body" })}\n\n`));
          controller.close();
          return;
        }

        // Pass-through: пересылаем чанки сразу, без буферизации по строкам — меньше задержка до первого байта
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (value?.length) controller.enqueue(value);
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ error: msg })}\n\n`));
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}
