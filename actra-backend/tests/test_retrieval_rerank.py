from src.memory.retrieval import _rerank_memories_for_query, _wants_secondary_retrieval


def test_temporal_rerank_orders_oldest_first():
    mems = [
        {"id": "b", "timestamp": 200.0, "content": "No, my name is Samuel"},
        {"id": "a", "timestamp": 100.0, "content": "Hi, my name is Sam Yu"},
    ]
    out = _rerank_memories_for_query("What was my previous name?", mems)
    assert out[0]["content"] == "Hi, my name is Sam Yu"


def test_no_rerank_when_not_temporal():
    mems = [
        {"id": "a", "timestamp": 100.0},
        {"id": "b", "timestamp": 200.0},
    ]
    out = _rerank_memories_for_query("What's the weather?", mems)
    assert out[0]["id"] == "a"


def test_secondary_retrieval_for_previous_name():
    assert _wants_secondary_retrieval("What's my previous name you remembered?") is True
