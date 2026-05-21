# identity v1 — security

## Where we are

- **Previous version:** `services/identity/v0-naive/` — read its source before building v1
- **Next version:** `v2-performance.md`

## Motivation — what v0 fails at

An OWASP Top-10 self-audit of v0 surfaces four serious problems:

- **A02 Cryptographic Failures** — SHA-256 unsalted is rainbow-table-vulnerable and computationally trivial to brute-force
- **A03 Injection** — no input validation; any string passes as email; empty passwords accepted
- **A07 Identification & Authentication Failures** — `/login` has no rate limit (online brute force trivial); JWTs never expire (stolen token = lifetime access)
- **A04 Insecure Design** — no refresh / rotation / logout mechanism

v1 addresses each specifically. Other classes of attack (enumeration, lockout, etc.) are deferred to later versions where they fit better.

## What v1 adds

### Password hashing — bcrypt

- `org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder` with strength 10
- Strength 10 calibrates to roughly 60–100 ms per hash on typical hardware in 2025 (verify with a one-time micro-benchmark, log to DESIGN.md)
- All SHA-256 hashing code from v0 is removed (deleted, not deprecated)
- Configuration knob: `app.security.bcrypt-strength` (default 10)

### Input validation — Bean Validation

- `jakarta.validation.constraints` on request DTOs
- Signup DTO:
  ```java
  record SignupRequest(
    @Email @Size(max = 255) String email,
    @NotBlank @Size(min = 12, max = 128) String password
  ) {}
  ```
- Login DTO:
  ```java
  record LoginRequest(
    @Email @Size(max = 255) String email,
    @NotBlank @Size(max = 128) String password
  ) {}
  ```
- Validation failures → 400 with body `{ "error": "VALIDATION_FAILED", "fields": { "<name>": "<message>" } }`

### Rate limiting — Bucket4j

- Library: `com.bucket4j:bucket4j_jdk17-core` (v8+; the artifact name uses an underscore — that is correct, not a typo)
- In-memory buckets keyed by source IP (use `X-Forwarded-For` first hop if present, otherwise `request.getRemoteAddr()`)
- Policies:
  - `/login`: 5 attempts per minute per IP (refill 1 token every 12s)
  - `/signup`: 3 attempts per minute per IP
- 429 response with `Retry-After` header (seconds until next token)
- Body: `{ "error": "RATE_LIMITED", "retryAfterSeconds": 12 }`

### Token expiry + refresh tokens

- Access token: 15-minute lifetime, `exp` claim enforced server-side on every authenticated request
- Refresh token: 256-bit random opaque value (Base64URL), stored as SHA-256 hash in DB, 30-day TTL
- **Rotation on use**: presenting a refresh token invalidates it and issues a new pair (access + refresh). Reusing the old refresh token returns 401.
- New endpoints:
  - `POST /refresh` body `{ "refreshToken": "<value>" }` → 200 `{ "accessToken": "...", "refreshToken": "..." }`
  - `POST /logout` (Authorization: Bearer <access>) → 204; revokes all of caller's active refresh tokens

### Data model additions

```sql
-- V2__refresh_tokens.sql
CREATE TABLE refresh_tokens (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash  CHAR(64)    NOT NULL UNIQUE,    -- SHA-256 hex
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked_at  TIMESTAMPTZ NULL
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id) WHERE revoked_at IS NULL;
```

### Dependencies (additions to v0's set)

```kotlin
dependencies {
  // ... everything from v0 ...

  implementation("org.springframework.boot:spring-boot-starter-validation")
  implementation("org.springframework.boot:spring-boot-starter-security") // brings BCryptPasswordEncoder
  implementation("com.bucket4j:bucket4j_jdk17-core:8.10.1")
}
```

Note on Spring Security: bringing in `spring-boot-starter-security` activates default auto-config including a default user — disable with:
```yaml
spring:
  autoconfigure:
    exclude:
      - org.springframework.boot.autoconfigure.security.servlet.UserDetailsServiceAutoConfiguration
```
And provide a `SecurityFilterChain` bean that permits the endpoints we want public (`/signup`, `/login`, `/refresh`) and requires JWT for `/me`, `/logout`.

### Configuration additions

```yaml
app:
  jwt:
    secret: ${JWT_SECRET:dev-only-secret-please-change}
    access-ttl-minutes: 15
    refresh-ttl-days: 30
  security:
    bcrypt-strength: 10
  ratelimit:
    login:
      capacity: 5
      refill-tokens-per-minute: 5
    signup:
      capacity: 3
      refill-tokens-per-minute: 3
```

## What v1 does NOT add (deferred)

- Index tuning, HikariCP tuning, query optimization → v2
- OAuth2 / social login → v3
- MFA → v4
- Observability (metrics, structured logs, traces) → v5
- Account lockout (per-user, regardless of IP), enumeration prevention, password reset, email verification, audit emission → v6

The Bucket4j rate limit in v1 is per-IP and easily bypassed by a botnet — that's a known limitation, v6 adds per-account lockout to complement it.

## Done criteria

1. v0's curl flow still works (signup, login, me)
2. A new user's `password_hash` in DB starts with `$2a$10$` or `$2b$10$` (bcrypt cost 10 format)
3. `POST /signup -d '{"email":"not-an-email","password":"x"}'` returns 400 with field-level errors
4. 10 rapid `POST /login` attempts with wrong password from one IP: first 5 are 401, 6th onward are 429 with `Retry-After`
5. JWT issued at time `t` is rejected after `t + 15m + clock_skew` (verifiable with a controllable clock in tests)
6. `POST /refresh` with valid refresh token → new pair; reusing the old refresh token → 401
7. `POST /logout` → subsequent `/refresh` with that user's most recent token → 401
8. `services/identity/v1-security/DESIGN.md` documents:
   - The OWASP findings from v0 and which v1 changes address each
   - The bcrypt-strength calibration (one-time micro-benchmark result)
   - The rate limit policy and its limitations (per-IP bypass note)
   - The access/refresh token lifecycle, including rotation semantics

## Tests

JUnit additions on top of v0's:
- `signup_withInvalidEmail_returns400`
- `signup_withShortPassword_returns400`
- `login_exceedsRateLimit_returns429`
- `accessToken_afterExpiry_isRejected` (use `Clock` abstraction)
- `refresh_thenReuseOldToken_returns401`
- `logout_thenRefresh_returns401`
- `passwordHash_inDatabase_isBcryptFormat`

## Compose overlay

`infra/compose/overlays/identity-v1.yml`:

```yaml
services:
  identity-v1:
    build:
      context: ../../../
      dockerfile: services/identity/v1-security/Dockerfile
    image: identity-v1:local
    ports:
      - "8102:8102"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
    depends_on:
      postgres:
        condition: service_healthy
```

## Claude Code prompt

```
Build identity v1-security.

Read service-plans-v2/identity/v1-security.md for the complete spec. Look at services/identity/v0-naive/ for v0's structure but do not import its code — v1 is a separate Gradle module that re-implements signup/login/me with bcrypt + validation + rate limiting + JWT expiry + refresh tokens, plus adds POST /refresh and POST /logout.

Create services/identity/v1-security/ as a new Gradle module containing:
- build.gradle.kts with all v0 dependencies PLUS the v1 additions listed in the spec
- application.yml with the v1 configuration
- Flyway migrations V1__init.sql (users table — same as v0) and V2__refresh_tokens.sql (per spec)
- src/main/java with:
  - Signup, login, me endpoints (re-implemented from scratch)
  - bcrypt hashing via BCryptPasswordEncoder strength 10
  - Bean Validation on request DTOs
  - A SecurityFilterChain bean configuring public endpoints and JWT-protected endpoints
  - A Bucket4j-based servlet filter for rate limiting on /signup and /login
  - JJWT 0.12 token issuer with 15-minute access tokens and exp claim enforcement
  - Refresh token issue + rotation + logout (revoke) flow
- src/test/java with all v0 tests PLUS the new tests listed in the spec
- A Dockerfile for port 8102
- DESIGN.md and README.md per the spec

Create infra/compose/overlays/identity-v1.yml with the contents shown in the spec.

The Bucket4j artifact is `com.bucket4j:bucket4j_jdk17-core:8.10.1` (the underscore in the artifact id is correct). If the resolution fails, try `com.bucket4j:bucket4j-core:8.x` as a fallback and update the spec accordingly.

Do NOT add indexes beyond v0's UNIQUE constraint (v2 handles index tuning). Do NOT add OAuth, MFA, observability, or anything from later versions. Do NOT modify v0. Do NOT run git commit.

When the done criteria are met, stop.
```
