import pytest

from src.config import Settings
from src.services.gemini_service import GeminiService


@pytest.mark.asyncio
async def test_analyze_intent_without_key():
    s = Settings(gemini_api_key="")
    g = GeminiService(s)
    r = await g.analyze_intent("hello")
    assert r["intent"] == "unknown"
