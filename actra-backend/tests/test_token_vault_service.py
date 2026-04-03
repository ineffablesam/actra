from unittest.mock import AsyncMock, MagicMock

import pytest

from src.config import Settings
from src.services.token_vault_service import TokenVaultService


@pytest.mark.asyncio
async def test_get_connected_providers_empty():
    s = Settings()
    redis = MagicMock()
    redis.get_json = AsyncMock(return_value=None)
    tv = TokenVaultService(s, redis)
    out = await tv.get_connected_providers("u1")
    assert out == []
