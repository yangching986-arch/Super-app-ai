-- Run after taking a full database backup, against the existing PostgreSQL database.
-- Safe to run if role column/table already exist.
ALTER TABLE users ADD COLUMN IF NOT EXISTS role VARCHAR(20) NOT NULL DEFAULT 'user';
CREATE TABLE IF NOT EXISTS user_api_keys (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id),
    provider VARCHAR(30) NOT NULL,
    encrypted_key TEXT NOT NULL,
    created TIMESTAMP WITHOUT TIME ZONE,
    updated TIMESTAMP WITHOUT TIME ZONE,
    CONSTRAINT uq_user_provider_key UNIQUE (user_id, provider)
);
CREATE INDEX IF NOT EXISTS ix_user_api_keys_user_id ON user_api_keys(user_id);
