"""Key bundle repository — Faz 2A.

Sözleşme:
  - upsert_bundle(): kullanıcının IK + SPK'sını yazar/günceller, OPK havuzunu
    yeni listeyle TAMAMEN değiştirir (rotation modeli).
  - fetch_bundle_consuming_opk(): tek bir OPK'yı atomik tüketir; havuz boşsa
    bundle'ı OPK'sız döner (SPK-only fallback).

Tüm public key alanları byte string olarak saklanır; istemcide base64url encode
edilip JSON üzerinden gelir.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from . import db


@dataclass(frozen=True)
class OneTimePreKey:
    opk_id: int
    public_key: bytes


@dataclass(frozen=True)
class FetchedBundle:
    handle: str
    identity_dh_key: bytes
    identity_sign_key: bytes
    signed_prekey_id: int
    signed_prekey: bytes
    spk_signature: bytes
    one_time_prekey: Optional[OneTimePreKey]  # None → SPK-only fallback


def upsert_bundle(
    *,
    handle: str,
    identity_dh_key: bytes,
    identity_sign_key: bytes,
    signed_prekey_id: int,
    signed_prekey: bytes,
    spk_signature: bytes,
    one_time_prekeys: list[OneTimePreKey],
) -> None:
    """Bundle'ı tek transaction'da upsert eder; OPK havuzunu da yeniden yazar."""
    with db.conn() as c, c.cursor() as cur:
        cur.execute(
            "INSERT INTO users (handle) VALUES (%s) "
            "ON CONFLICT (handle) DO NOTHING",
            (handle,),
        )
        cur.execute(
            """
            INSERT INTO key_bundles (
              handle, identity_dh_key, identity_sign_key,
              signed_prekey_id, signed_prekey, spk_signature,
              spk_created_at, updated_at
            ) VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW())
            ON CONFLICT (handle) DO UPDATE SET
              identity_dh_key   = EXCLUDED.identity_dh_key,
              identity_sign_key = EXCLUDED.identity_sign_key,
              signed_prekey_id  = EXCLUDED.signed_prekey_id,
              signed_prekey     = EXCLUDED.signed_prekey,
              spk_signature     = EXCLUDED.spk_signature,
              spk_created_at    = NOW(),
              updated_at        = NOW()
            """,
            (
                handle,
                identity_dh_key,
                identity_sign_key,
                signed_prekey_id,
                signed_prekey,
                spk_signature,
            ),
        )
        # OPK rotation: eskiyi sil, yeniyi yükle
        cur.execute("DELETE FROM one_time_prekeys WHERE handle = %s", (handle,))
        if one_time_prekeys:
            cur.executemany(
                "INSERT INTO one_time_prekeys (handle, opk_id, public_key) "
                "VALUES (%s, %s, %s)",
                [(handle, opk.opk_id, opk.public_key) for opk in one_time_prekeys],
            )


def fetch_bundle_consuming_opk(handle: str) -> Optional[FetchedBundle]:
    """Bundle'ı çek + bir OPK'yı atomik tüket.

    OPK havuzu boşsa one_time_prekey=None döner (SPK-only fallback).
    Kullanıcı yoksa None döner.
    """
    with db.conn() as c, c.cursor() as cur:
        cur.execute(
            """
            SELECT identity_dh_key, identity_sign_key, signed_prekey_id,
                   signed_prekey, spk_signature
              FROM key_bundles
             WHERE handle = %s
            """,
            (handle,),
        )
        row = cur.fetchone()
        if row is None:
            return None
        ik_dh, ik_sig, spk_id, spk, spk_sig = row

        # SKIP LOCKED ile concurrent fetch'lerde aynı OPK iki kez verilmez.
        cur.execute(
            """
            SELECT id, opk_id, public_key
              FROM one_time_prekeys
             WHERE handle = %s
             ORDER BY id
             FOR UPDATE SKIP LOCKED
             LIMIT 1
            """,
            (handle,),
        )
        opk_row = cur.fetchone()
        opk: Optional[OneTimePreKey] = None
        if opk_row is not None:
            row_id, opk_id, opk_pub = opk_row
            cur.execute("DELETE FROM one_time_prekeys WHERE id = %s", (row_id,))
            opk = OneTimePreKey(opk_id=int(opk_id), public_key=bytes(opk_pub))

        return FetchedBundle(
            handle=handle,
            identity_dh_key=bytes(ik_dh),
            identity_sign_key=bytes(ik_sig),
            signed_prekey_id=int(spk_id),
            signed_prekey=bytes(spk),
            spk_signature=bytes(spk_sig),
            one_time_prekey=opk,
        )


def opk_count(handle: str) -> int:
    """Test/diagnostic için OPK havuz boyutu."""
    with db.conn() as c, c.cursor() as cur:
        cur.execute(
            "SELECT COUNT(*) FROM one_time_prekeys WHERE handle = %s",
            (handle,),
        )
        row = cur.fetchone()
        return int(row[0]) if row else 0


def delete_user(handle: str) -> None:
    """Test temizliği için."""
    with db.conn() as c, c.cursor() as cur:
        cur.execute("DELETE FROM users WHERE handle = %s", (handle,))
