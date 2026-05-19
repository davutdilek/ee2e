"""Postgres bağlantı yardımcıları.

Faz 2A için psycopg ile kısa-ömürlü bağlantı kullanıyoruz. İleride trafik
artarsa connection pool'a (psycopg_pool) geçilecek.
"""
from __future__ import annotations

import os
from contextlib import contextmanager
from typing import Iterator

import psycopg


def _dsn() -> str:
    dsn = os.environ.get("DATABASE_URL")
    if not dsn:
        raise RuntimeError("DATABASE_URL not set")
    return dsn


@contextmanager
def conn() -> Iterator[psycopg.Connection]:
    """Bağlantıyı transaction-açık döndürür; with bloğu sonunda commit/rollback."""
    with psycopg.connect(_dsn(), connect_timeout=3) as c:
        try:
            yield c
            c.commit()
        except Exception:
            c.rollback()
            raise
