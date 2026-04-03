from __future__ import annotations

import asyncio
from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from cartesia import AsyncCartesia

from src.config import Settings
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "cartesia"


class CartesiaService:
    """
    Streams TTS audio using Cartesia's async WebSocket API (official client).
    """

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: AsyncCartesia | None = None
        self._contexts: dict[str, Any] = {}

    def _ensure_client(self) -> AsyncCartesia:
        if not self._settings.cartesia_api_key:
            logger.error(
                "cartesia_config_missing",
                service=_SERVICE,
                operation="ensure_client",
                reason="CARTESIA_API_KEY not set",
            )
            raise RuntimeError("CARTESIA_API_KEY not configured")
        if self._client is None:
            self._client = AsyncCartesia(api_key=self._settings.cartesia_api_key)
        return self._client

    async def stream_tts(
        self,
        text: str,
        session_id: str,
        on_chunk: Callable[[bytes], Awaitable[None]],
    ) -> None:
        if not text.strip():
            return
        try:
            client = self._ensure_client()
            output_format = {
                "container": "raw",
                "encoding": "pcm_f32le",
                "sample_rate": self._settings.cartesia_sample_rate,
            }
            async with client.tts.websocket_connect() as connection:
                ctx = connection.context(
                    context_id=session_id,
                    model_id=self._settings.cartesia_model_id,
                    voice={"mode": "id", "id": self._settings.cartesia_voice_id},
                    output_format=output_format,
                )
                self._contexts[session_id] = ctx
                try:
                    await ctx.push(transcript=text)
                    await ctx.no_more_inputs()
                    async for response in ctx.receive():
                        if response.type == "chunk" and response.audio:
                            await on_chunk(response.audio)
                        if response.type in ("done", "error"):
                            if response.type == "error":
                                err_msg = getattr(response, "error", None) or "unknown"
                                status = getattr(response, "status_code", None)
                                raise RuntimeError(
                                    f"cartesia_ws status={status} message={err_msg}"
                                )
                            break
                finally:
                    self._contexts.pop(session_id, None)
        except Exception as e:
            logger.error(
                "cartesia_stream_tts_failed",
                service=_SERVICE,
                operation="stream_tts",
                session_id=session_id,
                model_id=self._settings.cartesia_model_id,
                **err_ctx(e),
                exc_info=True,
            )
            raise

    async def cancel_stream(self, session_id: str) -> None:
        ctx = self._contexts.get(session_id)
        if ctx is not None:
            try:
                await ctx.cancel()
            except Exception as e:
                logger.warning(
                    "cartesia_cancel_failed",
                    service=_SERVICE,
                    operation="cancel_stream",
                    session_id=session_id,
                    **err_ctx(e),
                    exc_info=True,
                )
        await asyncio.sleep(0)
