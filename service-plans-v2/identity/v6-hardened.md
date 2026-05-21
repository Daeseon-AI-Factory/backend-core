# identity v6 — hardened

## Where we are

- **Previous version:** `services/identity/v5-observability/`
- **Depends on:** `pkg/audit` at any built version (v0+) — for security event emission
- **Final version** of the planned identity arc

## Motivation — what v5 fails at

v5 is observable but still has documented attack surface:

- **Account enumeration** — v2's short-circuit padded timing but the error responses still vary subtly (different shapes in error bodies, different log lines), and signup leaks existence via the UNIQUE constraint
- **Distributed brute force** — v1's Bucket4j is per-IP; a botnet with N IPs bypasses it. No per-account lockout exists.
- **No password reset** — users with forgotten passwords have no recovery path (must contact support manually)
- **Unverified emails on signup** — an attacker can squat on someone else's email; the rightful owner discovers it only when they try to sign up themselves
- **No audit trail** — v5 has metrics ("100 logins/minute") but no evidentiary record ("on May 21 14:02, user 42 logged in from IP-hash X via Google"). Security incident response needs the latter.

v6 closes each. This is the final planned version of identity.

## What v6 adds

### Account lockout (per-user)

- 5 consecutive failed logins for a user (regardless of source IP) → account locked for 30 minutes
- Failed counter resets on any successful login or after the lockout window expires
- Locked accounts: subsequent attempts return the same generic error as wrong-password (do NOT reveal lockout state to the attacker)
- Admin override: `POST /admin/users/{userId}/unlock` (requires admin role; for v6 the admin check is a placeholder via the `ADMIN_API_KEY` env var; later versions integrate with the authorization service)
- Lockout is checked BEFORE bcrypt verification (saves CPU during attack)

### Account enumeration prevention

- Signup, login, password-reset endpoints return semantically identical error messages for "no such user" vs "wrong password" vs "rate limited" vs "account locked"
- Response time padded to a constant target — 200 ms minimum — regardless of code path. Implementation: capture start time, run the path, compute remaining budget, sleep the delta with random jitter ±10ms (avoid creating a different observable signature)
- Signup returns 202 Accepted (not 201) and ALWAYS sends an email — does not reveal whether the email was already taken; the email content differs (welcome new user vs "someone tried to use your email")

### Password reset flow

- `POST /password/forgot` body `{ "email": "x@y.com" }` → always 202; if the user exists, generates a single-use token (256-bit random, Base64URL), stores its SHA-256 hash, emails the user a link with the raw token
- Token TTL: 1 hour
- `POST /password/reset` body `{ "token": "...", "newPassword": "..." }`:
  - Verifies token (look up hash, check not used, check not expired)
  - Validates new password per v1's rules (`@Size(min=12)`)
  - Updates password (bcrypt 10), marks token used, **revokes ALL refresh tokens for the user**, sends a "your password was changed" notification email
- Reset tokens cannot be used by a different user (token is bound to a user id internally)

### Email verification on signup

- New users created with `email_verified_at = NULL`
- Unverified users CANNOT log in (returns the same generic error as wrong-password)
- Signup sends a verification email with a single-use token (256-bit random)
- `GET /email/verify?token=...` → confirms (sets `email_verified_at = NOW()`), redirects to a success page (URL from env)
- `POST /email/resend-verification` body `{ "email": "..." }` → always 202; if user exists and is unverified, re-sends (rate-limited via Bucket4j: 3 per hour per email)

### Audit emission via pkg/audit

Every security-relevant event emits an audit record via `pkg/audit`:

- `identity.signup_initiated` — actor=anonymous, target=email (hashed)
- `identity.email_verified` — actor=user_id
- `identity.login_success` — actor=user_id, metadata: provider, correlation_id, ip_hash, user_agent_hash
- `identity.login_failure` — actor=user_id (when known) or email hash, metadata: reason, correlation_id, ip_hash
- `identity.logout` — actor=user_id
- `identity.mfa_enrolled` — actor=user_id
- `identity.mfa_disabled` — actor=user_id
- `identity.mfa_verification_success` / `mfa_verification_failure` — actor=user_id
- `identity.password_reset_requested` — actor=email_hash
- `identity.password_reset_completed` — actor=user_id
- `identity.account_locked` — actor=user_id, metadata: until
- `identity.account_unlocked` — actor=user_id, metadata: by (admin id)
- `identity.oauth_account_linked` / `oauth_account_unlinked` — actor=user_id, metadata: provider
- `identity.device_added` / `device_revoked` — actor=user_id, metadata: device_id

The `pkg/audit` API (whatever version is on main) accepts an event type + actor + target + metadata JSON.

### Suspicious activity signal (geo)

- Use MaxMind GeoLite2 City database (`com.maxmind.geoip2:geoip2`)
- Database file mounted at `/data/geoip/GeoLite2-City.mmdb` via the compose overlay (read-only)
- On login, look up country from the source IP
- If MFA-enrolled user logs in from a new country (never seen for this user before in `user_devices`-equivalent tracking), AND device fingerprint is new → emit `identity.suspicious_login` audit event AND require MFA even with a remembered device
- If the GeoLite2 file is absent at startup, the suspicious-activity check is disabled with a logged warning; the rest of v6 continues to work (graceful degradation)

### CAPTCHA hook (instrumented, optional)

- Config flag `app.security.captcha.enabled` (default false)
- When enabled, signup and password-reset endpoints require a `captchaToken` field in the body
- A pluggable `CaptchaVerifier` interface; default impl (`AlwaysAllowVerifier`) accepts any non-empty token (so local dev works); production deployments swap in an hCaptcha/reCAPTCHA verifier

### Dependencies

```kotlin
dependencies {
  // ... everything from v5 ...

  implementation("com.maxmind.geoip2:geoip2:4.2.1")

  // Depend on pkg/audit's most-recent built version.
  // The exact module path depends on which pkg/audit versions exist; for example:
  implementation(project(":pkg:audit:v0"))
}
```

### Data model additions

```sql
-- V6__hardening.sql
ALTER TABLE users
  ADD COLUMN email_verified_at TIMESTAMPTZ NULL,
  ADD COLUMN failed_login_count INT NOT NULL DEFAULT 0,
  ADD COLUMN locked_until TIMESTAMPTZ NULL;

CREATE TABLE email_verification_tokens (
  token_hash CHAR(64)    PRIMARY KEY,           -- SHA-256 hex
  user_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE password_reset_tokens (
  token_hash CHAR(64)    PRIMARY KEY,
  user_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at    TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_email_verify_user ON email_verification_tokens(user_id) WHERE used_at IS NULL;
CREATE INDEX idx_password_reset_user ON password_reset_tokens(user_id) WHERE used_at IS NULL;
```

Backfill consideration: existing users from v0-v5 migrations into v6's DB would have `email_verified_at = NULL` and thus be locked out by the new "must be verified to log in" rule. Since v6 lives in its own database (`identity_v6`), this doesn't break older versions, and v6 starts with an empty DB anyway.

### Configuration additions

```yaml
app:
  hardening:
    lockout:
      max-failures: 5
      lockout-duration-minutes: 30
    response-pad-millis: 200
    geoip:
      database-path: ${GEOIP_DB_PATH:/data/geoip/GeoLite2-City.mmdb}
    captcha:
      enabled: false
    email-verification:
      ttl-hours: 24
      resend-rate-limit-per-hour: 3
    password-reset:
      ttl-hours: 1
  notification:
    base-url: ${NOTIFICATION_BASE_URL:http://notification:8401}
  admin:
    api-key: ${ADMIN_API_KEY:dev-admin-key-please-change}
```

### Email sending

Calls the notification service (any version) at `NOTIFICATION_BASE_URL`. If notification is unreachable, the email send fails — but the operation that triggered it (signup, password reset request, etc.) still succeeds at the HTTP level; the failed send is logged + retried via a small in-process retry queue.

## What v6 does NOT add

- ML / heuristic fraud detection
- HSM-backed key storage
- Real CAPTCHA integration (only the hook + a no-op default verifier)
- Federated logout (revoking OAuth provider sessions when user logs out locally) — out of scope
- Encryption key rotation (the `MFA_AES_KEY` from v4 is still single-key in v6)

## Done criteria

1. v5's done criteria still hold (observability instrumentation intact and now emits audit events alongside)
2. 5 consecutive failed logins for a user → account locked → 6th attempt returns the generic invalid-credentials error → `identity.account_locked` audit event recorded
3. Lockout window expires → user can log in again
4. Password reset E2E:
   - `POST /password/forgot` always returns 202 (even for non-existent emails)
   - Valid token from email → `POST /password/reset` works → all refresh tokens for that user are invalidated → old access tokens expire normally on their 15-min schedule
5. Email verification:
   - New signup → `email_verified_at IS NULL` → login attempts return the standard "invalid credentials"
   - GET `/email/verify?token=...` with valid token → `email_verified_at` set → login now succeeds
6. Constant-time login: across 1000 samples each, the mean response time of unknown-email and wrong-password paths differ by less than 10% (DESIGN.md records the measurement)
7. Every event listed in "Audit emission" produces a row via `pkg/audit`'s API (verifiable by querying pkg/audit's store)
8. Suspicious-activity signal: with GeoLite2 mounted and an MFA-enrolled user, login from a new country fingerprint triggers MFA AND emits `identity.suspicious_login`
9. With GeoLite2 missing: service starts, logs warning, suspicious-activity check disabled, rest of v6 functional
10. DESIGN.md includes:
    - Threat model: what v6 defends against, what it doesn't
    - Constant-time login measurement methodology + result
    - Audit event catalog (the full list above)
    - Lockout policy rationale
    - Notification service dependency contract and degraded mode

## Tests

In addition to v5's:
- `consecutiveFailedLogins_lockAccount`
- `lockedAccount_returnsGenericError_notLockedSpecific`
- `lockedAccount_afterDuration_canLoginAgain`
- `passwordReset_validToken_invalidatesAllRefreshTokens`
- `passwordReset_expiredToken_returns400`
- `unverifiedSignup_cannotLogin`
- `emailVerify_validToken_enablesLogin`
- `loginResponseTime_constantAcrossPaths` (statistical test over many samples)
- `auditEvent_emittedFor_loginSuccess` (verify a row exists in pkg/audit store)
- `geolite2Missing_serviceStarts_suspiciousCheckDisabled`

## Compose overlay

`infra/compose/overlays/identity-v6.yml`:

```yaml
services:
  identity-v6:
    build:
      context: ../../../
      dockerfile: services/identity/v6-hardened/Dockerfile
    image: identity-v6:local
    ports:
      - "8107:8107"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
      MFA_AES_KEY: ${MFA_AES_KEY:-MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=}
      GOOGLE_CLIENT_ID: ${GOOGLE_CLIENT_ID:-}
      GOOGLE_CLIENT_SECRET: ${GOOGLE_CLIENT_SECRET:-}
      GITHUB_CLIENT_ID: ${GITHUB_CLIENT_ID:-}
      GITHUB_CLIENT_SECRET: ${GITHUB_CLIENT_SECRET:-}
      OTEL_EXPORTER_OTLP_ENDPOINT: ${OTEL_EXPORTER_OTLP_ENDPOINT:-http://otel-collector:4318}
      NOTIFICATION_BASE_URL: ${NOTIFICATION_BASE_URL:-http://notification-v0:8401}
      GEOIP_DB_PATH: /data/geoip/GeoLite2-City.mmdb
      ADMIN_API_KEY: ${ADMIN_API_KEY:-dev-admin-key}
    volumes:
      - ${HOST_GEOIP_PATH:-./geoip}:/data/geoip:ro
    depends_on:
      postgres:
        condition: service_healthy
```

Note: `${HOST_GEOIP_PATH:-./geoip}` lets the user mount their own MaxMind file location. The `:ro` makes the mount read-only. The directory may be empty (no .mmdb inside) — v6 handles that gracefully.

## Claude Code prompt

```
Build identity v6-hardened. This is the final planned version of identity.

Read service-plans-v2/identity/v6-hardened.md. Look at services/identity/v5-observability/ for v5's structure. Re-implement v5's functionality in a new module services/identity/v6-hardened/ with all v6 additions: lockout, enumeration prevention, password reset, email verification, audit emission, geo signal, CAPTCHA hook.

Copy v5's Flyway migrations V1-V5 into the new module unchanged; ADD V6__hardening.sql per the spec.

Depend on pkg/audit at the highest version present in pkg/audit/. Check which versions exist with `ls pkg/audit/` before writing the build.gradle.kts dependency; pick the highest.

Email sending: use Spring's RestClient to POST to NOTIFICATION_BASE_URL/notify with `{ to, subject, body }`. Wrap in a small retry queue (in-memory, like notification v1's pattern) so a transient notification outage doesn't break signup/password-reset flows.

For the constant-time login: measure the maximum cost path (full bcrypt verify) at startup; cache that target; pad faster paths to within ±10ms jitter.

If GeoLite2 file is missing at /data/geoip/GeoLite2-City.mmdb, log a clear WARN and disable the suspicious-activity check (do NOT fail to start).

Database: identity_v6. Port: 8107. Compose overlay per the spec.

Do NOT modify earlier versions. Do NOT run git commit.

Stop when the done criteria are met. After this is done, the identity service evolution is complete.
```
