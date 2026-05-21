# identity v4 — mfa

## Where we are

- **Previous version:** `services/identity/v3-oauth/`
- **Next version:** `v5-observability.md`

## Motivation — what v3 fails at

Even with OAuth2 in v3, the account is only as secure as the weakest factor used to access it. Common attacks v3 cannot resist:

- **Phishing** — user enters credentials on a lookalike page; attacker captures the password
- **Password reuse** — a breach on another service exposes the same email + password; attacker logs in here
- **OAuth provider account takeover** — Google account compromise gives access to anything linked

TOTP (Time-based One-Time Password, RFC 6238) adds a clock-bound 6-digit factor that:
- Cannot be phished (the code expires in 30 seconds)
- Cannot be replayed (single-use per 30-second window)
- Doesn't require an extra service (no SMS, no provider dependency)

WebAuthn / passkeys would be stronger but are out of scope for v4 (would naturally be v7).

## What v4 adds

### TOTP enrollment

`POST /mfa/totp/enroll` (Authorization: Bearer <jwt> required) →
```json
{
  "secret": "JBSWY3DPEHPK3PXP",
  "qrCodeUri": "otpauth://totp/PlatformName:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=PlatformName&algorithm=SHA1&digits=6&period=30",
  "recoveryCodes": ["XXXX-XXXX-XX", "XXXX-XXXX-XX", ...]
}
```

- Secret: 20 random bytes, Base32-encoded (TOTP standard)
- Recovery codes: 10 codes, format `XXXX-XXXX-XX` (10 alphanumeric chars + dash for readability), stored as bcrypt hashes
- Returned **exactly once**; client must save them at this moment
- Secret persisted **encrypted at rest** (AES-256-GCM with key from env)
- TOTP is "pending" until confirmed by `POST /mfa/totp/confirm`

`POST /mfa/totp/confirm` body `{ "code": "123456" }` → confirms enrollment with a valid current TOTP code. Until confirmed, login is unaffected. After confirmed, MFA is enforced on subsequent logins.

`DELETE /mfa/totp` body `{ "code": "123456" }` → removes TOTP. Requires a valid current TOTP code (so a compromised session cannot disable MFA without the device).

### Two-step login when MFA enrolled

When MFA is confirmed for a user, the login response changes:

`POST /login` (existing) → if MFA enrolled, returns 200 with:
```json
{ "mfaRequired": true, "mfaSessionToken": "<opaque>" }
```
Instead of an access token. The `mfaSessionToken` is a short-lived (5 minute) single-purpose token stored in `mfa_session_tokens`.

`POST /login/mfa` body `{ "mfaSessionToken": "...", "code": "123456" }`:
- Code accepted: a current TOTP code OR an unused recovery code
- On success: marks the mfaSessionToken used, issues the standard access + refresh pair
- On failure: 401, the mfaSessionToken can be retried up to 5 times before being burned

OAuth login: after OAuth callback, if the linked user has MFA enrolled, the same two-step kicks in — return `mfaRequired` rather than the final pair.

### Recovery codes

- 10 codes generated at enrollment, single-use each
- Stored as bcrypt hashes
- `POST /mfa/recovery-codes/regenerate` (Authorization + current TOTP code in body required) → invalidates existing codes, issues 10 new ones returned exactly once

### Device tracking

On every successful login, record:
- `user_agent_hash` (SHA-256 of the User-Agent header)
- `ip_hash` (SHA-256 of the IP address — hash, not the IP, for privacy)
- `first_seen_at`, `last_seen_at`

Endpoints:
- `GET /me/devices` → list devices
- `DELETE /me/devices/{id}` → revoke (forces re-login + MFA on next attempt with that fingerprint)

For users with MFA enrolled: a new device (no row in `user_devices` for the user with matching UA-hash + IP-hash) triggers an MFA challenge even with a valid refresh token.

### Data model additions

```sql
-- V5__mfa.sql
CREATE TABLE mfa_totp_secrets (
  user_id          BIGINT      PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  secret_encrypted BYTEA       NOT NULL,
  confirmed_at     TIMESTAMPTZ NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE mfa_recovery_codes (
  id         BIGSERIAL   PRIMARY KEY,
  user_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash  VARCHAR(60) NOT NULL,
  used_at    TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_codes_user_unused
  ON mfa_recovery_codes(user_id)
  WHERE used_at IS NULL;

CREATE TABLE user_devices (
  id              BIGSERIAL   PRIMARY KEY,
  user_id         BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  user_agent_hash CHAR(64)    NOT NULL,
  ip_hash         CHAR(64)    NOT NULL,
  first_seen_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at      TIMESTAMPTZ NULL,
  UNIQUE (user_id, user_agent_hash, ip_hash)
);

CREATE TABLE mfa_session_tokens (
  token        CHAR(64)    PRIMARY KEY,         -- SHA-256 hex of the opaque value
  user_id      BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at   TIMESTAMPTZ NOT NULL,
  attempts     INT         NOT NULL DEFAULT 0,
  used_at      TIMESTAMPTZ NULL
);
```

### Dependencies

```kotlin
dependencies {
  // ... everything from v3 ...

  // TOTP — Sam Stevens' library, the de-facto standard in Java
  implementation("dev.samstevens.totp:totp:1.7.1")
}
```

The TOTP library handles secret generation, QR URI building, and code verification (with a configurable time-skew window — default ±1 step, i.e., ±30s; keep that default).

### Secret encryption

- Algorithm: AES-256-GCM
- Key: from env var `MFA_AES_KEY` (Base64-encoded 32 bytes); generated on first deploy and never rotated in v4 (key rotation lives in v6+)
- Format stored: 12-byte nonce || 16-byte tag || ciphertext (all concatenated)
- Implementation: standard `javax.crypto.Cipher` with transformation `AES/GCM/NoPadding`

If `MFA_AES_KEY` is missing at startup, the service fails fast (no fallback to plaintext storage).

### Configuration additions

```yaml
app:
  mfa:
    totp:
      issuer: PlatformName
      time-step-seconds: 30
      time-skew-steps: 1
    session-token-ttl-minutes: 5
    session-token-max-attempts: 5
    aes-key-env: MFA_AES_KEY
```

## What v4 does NOT add

- WebAuthn / passkeys → out of scope (future v7)
- SMS-based 2FA — belongs in the notification service, not here
- Hardware tokens — out of scope
- Observability of MFA events → v5 (this version just persists and logs to console)
- Audit-grade emission of MFA enroll/disable → v6 (via pkg/audit)
- AES key rotation → v6 or beyond

## Done criteria

1. v3's done criteria still hold (password, OAuth, refresh, logout work; OAuth-linked users not broken by MFA changes)
2. Enrollment E2E:
   - `POST /mfa/totp/enroll` returns secret + QR URI + 10 recovery codes
   - Scanning the QR URI in Google Authenticator / Authy / 1Password yields valid codes
   - `POST /mfa/totp/confirm` with a current code succeeds
3. Login flow after enrollment:
   - `POST /login` → 200 with `mfaRequired: true, mfaSessionToken`
   - `POST /login/mfa` with a valid TOTP code → 200 with access + refresh
4. Recovery code: `POST /login/mfa` with an unused recovery code works; second use of the same code → 401
5. mfaSessionToken: 6th wrong attempt → token burned (cannot be reused even with correct code)
6. Device tracking: `GET /me/devices` shows the device used to log in
7. Encrypted secret: in the DB, `secret_encrypted` is binary (nonce || tag || ciphertext); not plaintext readable
8. AES key missing → service fails to start (no plaintext fallback)
9. `services/identity/v4-mfa/DESIGN.md` documents:
   - TOTP basics (HMAC-SHA1, 30s step, 6 digits per RFC 6238)
   - Two-step login sequence
   - Recovery code threat model (why bcrypt-hashed, why single-use)
   - The encryption scheme + key management note (single key, no rotation in v4)

## Tests

In addition to v3's tests:
- `enroll_thenConfirm_thenLogin_requiresMfa`
- `enroll_confirmWithBadCode_returns401`
- `mfaLogin_withRecoveryCode_succeedsOnce`
- `mfaSession_after5Failures_isBurned`
- `secretInDatabase_isEncrypted` (binary, not the original Base32 secret)
- `serviceStartup_withoutAesKey_fails`

## Compose overlay

`infra/compose/overlays/identity-v4.yml`:

```yaml
services:
  identity-v4:
    build:
      context: ../../../
      dockerfile: services/identity/v4-mfa/Dockerfile
    image: identity-v4:local
    ports:
      - "8105:8105"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
      MFA_AES_KEY: ${MFA_AES_KEY:-MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=}  # 32 bytes Base64 for dev only
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID:-}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET:-}
    depends_on:
      postgres:
        condition: service_healthy
```

(The default `MFA_AES_KEY` shown is a placeholder 32-byte value. Generate a real one for any non-local environment.)

## Claude Code prompt

```
Build identity v4-mfa.

Read service-plans-v2/identity/v4-mfa.md. Look at services/identity/v3-oauth/ for v3's structure. Re-implement v3's functionality in a new module services/identity/v4-mfa/ with TOTP enrollment, two-step login, recovery codes, and device tracking added.

Copy v3's Flyway migrations V1-V4 into the new module unchanged; ADD V5__mfa.sql per the spec.

Use the TOTP library `dev.samstevens.totp:totp:1.7.1`. It exposes a fluent builder API for secret generation and a CodeVerifier for validation. Use its default time-step (30s) and default skew window (±1 step).

Encrypt TOTP secrets with AES-256-GCM using the key from MFA_AES_KEY env var. If the env var is missing or not exactly 32 bytes (after Base64 decode), the service must fail to start with a clear error message.

Database: identity_v4. Port: 8105. Compose overlay per the spec.

Do NOT add observability (v5), hardening (v6), or audit emission. Do NOT add WebAuthn or SMS-based 2FA. Do NOT modify earlier versions. Do NOT run git commit.

Stop when the done criteria are met.
```
