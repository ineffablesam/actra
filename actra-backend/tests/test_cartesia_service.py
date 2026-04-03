import pytest

from src.config import Settings
from src.services.cartesia_service import CartesiaService


@pytest.mark.asyncio
async def test_cartesia_requires_key():
    s = Settings(cartesia_api_key="")
    c = CartesiaService(s)
    chunks: list[bytes] = []

    async def on_chunk(b: bytes) -> None:
        chunks.append(b)

    with pytest.raises(RuntimeError):
        await c.stream_tts("hi", "sid", on_chunk)
