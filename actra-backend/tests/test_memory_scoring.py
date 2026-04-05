from src.memory.scoring import score_message_importance


def test_casual_skipped():
    r = score_message_importance("hi")
    assert r.should_store is False


def test_remember_high():
    r = score_message_importance("Please remember I prefer morning meetings")
    assert r.should_store is True
    assert r.score >= 0.8


def test_app_action_medium():
    r = score_message_importance("Connect my Gmail and check my inbox for invoices")
    assert r.should_store is True
    assert 0.5 <= r.score <= 0.75
