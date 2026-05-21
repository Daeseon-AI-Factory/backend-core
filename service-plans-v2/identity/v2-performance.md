# identity v2 — performance

## Where we are

- **Previous version:** `services/identity/v1-security/`
- **Next version:** `v3-oauth.md`

## Motivation — what v1 fails at

Run k6 against v1 with a ramping scenario (1 → 200 VUs over 2 minutes, hitting `/login` with valid creds for an existing user). v1 will exhibit:

- p99 of `/login` rising past 800 ms above ~50 RPS
- HikariCP pool exhaustion errors above ~30 concurrent requests:
  ```
  org.springframework.jdbc.CannotGetJdbcConnectionException:
    HikariPool-1 - Connection is not available, request timed out after 30000ms
  ```
- `EXPLAIN ANALYZE` on the login query:
  - For "user exists" path: index scan via the UNIQUE constraint on email — already fast
  - For "user does not exist" path: same index scan, BUT the response time is dominated by bcrypt verification of a placeholder string (anti-enumeration cost)

The pool exhaustion and the symmetric-cost login path are the real wins available without changing security guarantees. This version is performance only — no functional behavior changes from a caller's perspective.

## What v2 adds

### Explicit index strategy

```sql
-- V3__performance_indexes.sql
-- Partial index aligned with the lookup pattern. Once v6 adds soft-delete (deleted_at)
-- this index will naturally exclude soft-deleted rows; for now `deleted_at` does not
-- exist yet so we use a non-partial index. v6 will switch to partial.
CREATE INDEX IF NOT EXISTS idx_users_email_lookup ON users (email);

-- Refresh tokens are looked up by token_hash on /refresh hot path.
-- UNIQUE already created an index in v1; we add a partial index for active tokens only.
CREATE INDEX idx_refresh_tokens_active
  ON refresh_tokens (token_hash)
  WHERE revoked_at IS NULL;
```

Capture `EXPLAIN ANALYZE` output for the three hot queries in DESIGN.md (before vs after).

### HikariCP tuning

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 30
      minimum-idle: 5
      connection-timeout: 5000
      idle-timeout: 600000
      max-lifetime: 1800000
      leak-detection-threshold: 30000
      pool-name: identity-v2-pool
```

Rationale (must appear in DESIGN.md):
- `maximum-pool-size: 30` — sized for ~100 effective concurrent users at typical query times; Postgres default `max_connections` is 100 so 30 leaves headroom for other services on shared Postgres
- `connection-timeout: 5000` — fail fast rather than queue indefinitely
- `idle-timeout: 600000` / `max-lifetime: 1800000` — standard HikariCP recommendations
- `leak-detection-threshold: 30000` — warn if a connection is held > 30s (catches code mistakes early)

### Login short-circuit (constant-time-ish)

The login flow becomes:

1. Look up user by email (indexed)
2. If user does not exist:
   - **Do NOT** run bcrypt against a placeholder (v1's anti-enumeration trick) — that wastes CPU on every failed-email attempt
   - Instead, sleep for the expected bcrypt duration measured at startup (one-time benchmark)
   - Return the same error response shape as wrong-password
3. If user exists: bcrypt verify the password normally

This is an explicit time-budget approach. v6 adds full enumeration prevention; this is the perf-friendly partial measure.

DESIGN.md must include the measurement methodology and observed response-time spread between "unknown email" and "wrong password" paths.

### k6 baseline script

Add `load-tests/identity-v2/login-baseline.js`:

```javascript
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '60s', target: 200 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(99)<250'],   // v2 target
    http_req_failed: ['rate<0.01'],
  },
};

export default function () {
  const res = http.post(`${__ENV.BASE_URL}/login`, JSON.stringify({
    email: 'test@example.com',
    password: 'hunter2hunter2'
  }), { headers: { 'Content-Type': 'application/json' } });
  check(res, { '200': r => r.status === 200 });
}
```

Run against v1 first to capture the "before" baseline; then against v2 for the "after". Both numbers go into DESIGN.md.

### Dependencies

No new dependencies. v2 is configuration + SQL + a small bit of Java logic; everything is already in v1's classpath.

## What v2 does NOT add

- Redis caching — identity lookups with the index are already fast enough; introducing Redis would add latency, complexity, and a coherence problem with no clear benefit
- OAuth2 / social login → v3
- MFA → v4
- Observability → v5
- Hardening (lockout, enumeration prevention, password reset, email verify, audit) → v6

## Done criteria

1. All v1 done criteria still hold (security mechanisms intact)
2. Migration `V3__performance_indexes.sql` runs cleanly; `\d users` and `\d refresh_tokens` in psql show the new indexes
3. `EXPLAIN ANALYZE` on the login query shows index scan (not seq scan); the output is captured in DESIGN.md
4. k6 baseline (`load-tests/identity-v2/login-baseline.js`) against v2 meets `p(99)<250ms` at 200 VUs
5. Connection pool: no `Connection is not available` errors in logs during the k6 run
6. Response-time difference between "unknown email" and "wrong password" paths is < 20% in 1000-sample measurement
7. DESIGN.md includes:
   - Before/after k6 numbers (against v1 vs v2) — p50, p95, p99, error rate
   - `EXPLAIN ANALYZE` before/after for the login query
   - HikariCP rationale per the values above
   - Login short-circuit measurement methodology and result

## Compose overlay

`infra/compose/overlays/identity-v2.yml`:

```yaml
services:
  identity-v2:
    build:
      context: ../../../
      dockerfile: services/identity/v2-performance/Dockerfile
    image: identity-v2:local
    ports:
      - "8103:8103"
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
Build identity v2-performance.

Read service-plans-v2/identity/v2-performance.md for the spec. Look at services/identity/v1-security/ for v1's structure and re-implement it in a new module services/identity/v2-performance/ with the v2 changes (indexes via Flyway migration V3, HikariCP tuning in application.yml, login short-circuit with constant-time padding instead of v1's bcrypt-against-placeholder).

Copy v1's Flyway migrations V1 and V2 into the new module unchanged; ADD V3__performance_indexes.sql per the spec.

Capture EXPLAIN ANALYZE output for the login query into DESIGN.md. If k6 is available in the dev environment, run the load-tests/identity-v2/login-baseline.js script against v1 first (capturing the "before" numbers) then against v2 ("after"). If k6 is not available, leave clearly-marked TODO placeholders in DESIGN.md and continue.

Database: identity_v2. Port: 8103. Compose overlay per the spec.

Do NOT add OAuth, MFA, observability, or hardening features. Do NOT modify earlier versions. Do NOT run git commit.

Stop when the done criteria are met.
```
