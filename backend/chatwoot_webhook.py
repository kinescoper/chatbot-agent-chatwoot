"""
Chatwoot webhook handler: bot mode (reply to customer) and copilot mode (private suggestion).
Subscribe to message_created; use conversation (or contact) custom attribute support_mode: "bot" | "human".

Portable: no dependency on a specific RAG/LLM. Set reply provider via set_reply_provider(get_reply)
so any project can plug in its own AI backend (e.g. RAG+LLM, another API).
"""
from __future__ import annotations

import logging
import os
from typing import Any, Callable

from fastapi import APIRouter, BackgroundTasks, Request
from pydantic import BaseModel, Field

from backend.chatwoot_client import is_configured, post_message

logger = logging.getLogger(__name__)

SUPPORT_MODE_ATTR = os.environ.get("CHATWOOT_SUPPORT_MODE_ATTR", "support_mode")
COPILOT_PREFIX = "[RAG suggestion – use or edit]\n\n"

# Reply provider: (message: str) -> str | None. Injected by the host app (e.g. RAG backend).
ReplyProvider = Callable[[str], str | None]
_reply_provider: ReplyProvider | None = None


def set_reply_provider(provider: ReplyProvider | None) -> None:
    """Set the function used to generate replies (e.g. RAG+LLM). Required for webhook to work."""
    global _reply_provider
    _reply_provider = provider


def get_reply_provider() -> ReplyProvider | None:
    return _reply_provider


router = APIRouter(prefix="/chatwoot", tags=["chatwoot"])


class WebhookPayload(BaseModel):
    """Chatwoot webhook body (flexible)."""
    event: str = ""
    id: str | int | None = None
    content: str = ""
    message_type: str = ""
    content_type: str = "text"
    sender: dict[str, Any] | None = None
    contact: dict[str, Any] | None = None
    conversation: dict[str, Any] | None = None

    class Config:
        extra = "allow"


def _support_mode(payload: WebhookPayload) -> str:
    """Return 'bot' | 'human' from conversation or contact custom_attributes (Pre Chat Form or SDK)."""
    for source in (payload.conversation, payload.contact):
        if not source:
            continue
        attrs = source.get("custom_attributes") or source.get("additional_attributes") or {}
        mode = (attrs.get(SUPPORT_MODE_ATTR) or attrs.get("preferred_channel") or "").strip().lower()
        if mode in ("bot", "human"):
            return mode
    return "human"


def _conversation_id(payload: WebhookPayload) -> int | None:
    """Numeric conversation id for API."""
    conv = payload.conversation or {}
    cid = conv.get("id")
    if cid is not None:
        try:
            return int(cid)
        except (TypeError, ValueError):
            pass
    return None


def _process_message(payload: WebhookPayload) -> None:
    """Call reply provider and post reply (public for bot, private for copilot)."""
    if not is_configured():
        logger.warning("Chatwoot client not configured; skipping webhook processing")
        return
    provider = get_reply_provider()
    if not provider:
        logger.warning("Reply provider not set; skipping webhook processing")
        return
    cid = _conversation_id(payload)
    if cid is None:
        logger.warning("No conversation id in webhook payload")
        return
    content = (payload.content or "").strip()
    if not content:
        return
    reply = provider(content)
    if not reply:
        return
    mode = _support_mode(payload)
    if mode == "bot":
        post_message(cid, reply, private=False)
    else:
        post_message(cid, COPILOT_PREFIX + reply, private=True)


class CopilotRequest(BaseModel):
    """Request body for /copilot (suggestion only, no post to Chatwoot)."""
    message: str = Field(..., min_length=1)


class CopilotResponse(BaseModel):
    suggestion: str


@router.post("/copilot", response_model=CopilotResponse)
def copilot_suggest(req: CopilotRequest) -> CopilotResponse:
    """
    Return AI suggestion for the given message (for operators).
    Does not post to Chatwoot; operator can use or edit the text.
    """
    provider = get_reply_provider()
    reply = (provider(req.message) if provider else None) or ""
    return CopilotResponse(suggestion=reply)


@router.post("/webhook")
async def webhook(request: Request, background_tasks: BackgroundTasks) -> dict[str, str]:
    """
    Chatwoot webhook: message_created.
    - Incoming only; bot mode -> post public reply; human mode -> post private suggestion.
    """
    try:
        body = await request.json()
    except Exception:
        return {"status": "ok"}
    payload = WebhookPayload(
        event=body.get("event", ""),
        id=body.get("id"),
        content=body.get("content", ""),
        message_type=body.get("message_type", ""),
        content_type=body.get("content_type", "text"),
        sender=body.get("sender"),
        contact=body.get("contact"),
        conversation=body.get("conversation"),
    )
    if payload.event != "message_created":
        return {"status": "ok"}
    if payload.message_type != "incoming":
        return {"status": "ok"}
    background_tasks.add_task(_process_message, payload)
    return {"status": "ok"}
