-- EE2E — Initial schema (Faz 2A)
-- Faz 1: yapı kurulur, tablolar boş kalır.
-- Faz 2A: key_bundles ve one_time_prekeys gerçekten kullanılmaya başlar.
-- Faz 2B: X3DH SK türetme tamamen istemcide; sunucu sadece public key dağıtır.
-- HİÇBİR private key veya plaintext message bu DB'ye yazılmaz.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    handle      TEXT PRIMARY KEY,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Public bundle. Bir kullanıcı (handle) için tek satır.
-- Identity Key iki parçaya ayrıldı:
--   identity_dh_key  : X25519 pub  (DH için, X3DH'de kullanılır)
--   identity_sign_key: Ed25519 pub (imza için, SPK signature doğrulamasında)
CREATE TABLE IF NOT EXISTS key_bundles (
    handle             TEXT PRIMARY KEY REFERENCES users(handle) ON DELETE CASCADE,
    identity_dh_key    BYTEA NOT NULL,
    identity_sign_key  BYTEA NOT NULL,
    signed_prekey_id   INT   NOT NULL,
    signed_prekey      BYTEA NOT NULL,
    spk_signature      BYTEA NOT NULL,
    spk_created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tek kullanımlık prekey havuzu. Her satır bir OPK; tüketilince SİLİNİR.
-- Atomik tüketim için fetch sırasında: SELECT ... FOR UPDATE SKIP LOCKED + DELETE
CREATE TABLE IF NOT EXISTS one_time_prekeys (
    id          BIGSERIAL PRIMARY KEY,
    handle      TEXT NOT NULL REFERENCES users(handle) ON DELETE CASCADE,
    opk_id      INT  NOT NULL,
    public_key  BYTEA NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (handle, opk_id)
);

CREATE INDEX IF NOT EXISTS idx_opk_handle ON one_time_prekeys (handle);

-- Mesaj tablosu YOK. Mesajlar disk'e ASLA yazılmaz.
-- Faz 1'de in-memory queue, Faz 3'te Redis (TTL).
