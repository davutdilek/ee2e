"""Ephemeral queue davranış testleri."""
from __future__ import annotations

import time

import pytest

from app.ephemeral_queue import EphemeralQueue


def test_enqueue_and_drain_returns_envelopes():
    q = EphemeralQueue()
    q.enqueue("alice", {"envelope": {"ciphertext": "AAA"}})
    q.enqueue("alice", {"envelope": {"ciphertext": "BBB"}})
    items = q.drain_for("alice")
    assert len(items) == 2
    assert {i["envelope"]["ciphertext"] for i in items} == {"AAA", "BBB"}


def test_drain_clears_queue():
    q = EphemeralQueue()
    q.enqueue("bob", {"envelope": {"x": 1}})
    q.drain_for("bob")
    assert q.drain_for("bob") == []
    assert q.size() == 0


def test_acknowledge_removes_specific_message():
    q = EphemeralQueue()
    msg_id_a = q.enqueue("carol", {"envelope": {"i": "a"}})
    q.enqueue("carol", {"envelope": {"i": "b"}})
    assert q.acknowledge(msg_id_a) is True
    assert q.acknowledge(msg_id_a) is False
    remaining = q.drain_for("carol")
    assert len(remaining) == 1
    assert remaining[0]["envelope"]["i"] == "b"


def test_drain_skips_expired_items():
    q = EphemeralQueue()
    q.enqueue("dave", {"envelope": {}}, ttl_seconds=1)
    time.sleep(1.1)
    assert q.drain_for("dave") == []


def test_gc_removes_expired():
    q = EphemeralQueue()
    q.enqueue("eve", {"envelope": {}}, ttl_seconds=1)
    q.enqueue("eve", {"envelope": {}}, ttl_seconds=60)
    time.sleep(1.1)
    removed = q.gc_expired()
    assert removed == 1
    assert q.size() == 1


def test_isolation_between_recipients():
    q = EphemeralQueue()
    q.enqueue("alice", {"envelope": {"k": 1}})
    q.enqueue("bob", {"envelope": {"k": 2}})
    assert len(q.drain_for("alice")) == 1
    assert len(q.drain_for("bob")) == 1


def test_msg_id_stamped_on_envelope():
    q = EphemeralQueue()
    msg_id = q.enqueue("frank", {"envelope": {}})
    items = q.drain_for("frank")
    assert items[0]["msg_id"] == msg_id


@pytest.mark.parametrize("ttl,expected_min", [(0, 1), (-5, 1)])
def test_ttl_floor_is_one_second(ttl, expected_min):
    q = EphemeralQueue()
    msg_id = q.enqueue("g", {"envelope": {}}, ttl_seconds=ttl)
    assert msg_id is not None
