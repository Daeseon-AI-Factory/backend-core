# identity v0 — naive

## Where we are

- **Previous version:** none. First version.
- **Next version:** `v1-security.md`
- **Service overview:** `README.md` in this folder

## Motivation

First version. Establish baseline signup/login/me with deliberately weak security so v1 has a concrete OWASP-style audit to respond to. Every weakness in this version is intentional and documented.

## What v0 builds

### Endpoints

| Method | Path | Request | Success Response |
|---|---|---|---|
| POST | `/signup` | `{ "email": "x@y.com", "password": "anything" }` | 201 `{ "id": 1, "email": "x@y.com" }` |
| POST | `/login` | `{ "email": "x@y.com", "password": "anything" }` | 200 `{ "token": "<jwt>" }` |
| GET  | `/me`   | Header `Authorization: Bearer <jwt>` | 200 `{ "id": 1, "email": "x@y.com" }` |

Errors return JSON `{ "error": "<code>", "message": "<text>" }` with appropriate HTTP status.

### Data model (Postgres)

```sql
-- V1__init.sql
CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  email         VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(64)  NOT NULL,    -- SHA-256 hex = 64 chars
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
```

Notes:
- `email` is UNIQUE; Postgres auto-creates a B-tree index for the constraint. Treat this as incidental for v0. v2 explicitly tunes indexes.
- Only one Flyway migration (`V1__init.sql`).

### Dependencies (Gradle Kotlin DSL)

In `services/identity/v0-naive/build.gradle.kts`:

```kotlin
plugins {
  java
  id("org.springframework.boot") version "3.4.0"
  id("io.spring.dependency-management") version "1.1.6"
}

java {
  sourceCompatibility = JavaVersion.VERSION_21
}

dependencies {
  implementation("org.springframework.boot:spring-boot-starter-web")
  implementation("org.springframework.boot:spring-boot-starter-data-jpa")
  implementation("org.flywaydb:flyway-core")
  runtimeOnly("org.postgresql:postgresql")

  // JWT — JJWT 0.12.x is the modern API
  implementation("io.jsonwebtoken:jjwt-api:0.12.6")
  runtimeOnly("io.jsonwebtoken:jjwt-impl:0.12.6")
  runtimeOnly("io.jsonwebtoken:jjwt-jackson:0.12.6")

  testImplementation("org.springframework.boot:spring-boot-starter-test")
}
```

(Spring Boot version is illustrative — use whatever the root project pins. Same for dependency-management.)

### Configuration

`application.yml`:

```yaml
server:
  port: 8101
spring:
  application:
    name: identity-v0
  datasource:
    url: jdbc:postgresql://${DB_HOST:postgres}:5432/identity_v0
    username: ${DB_USER:postgres}
    password: ${DB_PASSWORD:postgres}
  jpa:
    hibernate:
      ddl-auto: validate    # Flyway owns the schema
  flyway:
    baseline-on-migrate: true

app:
  jwt:
    secret: ${JWT_SECRET:dev-only-secret-please-change}   # min 256 bits for HS256
```

### Hashing (intentionally weak)

Use `java.security.MessageDigest.getInstance("SHA-256")`, take the hex of the digest, store as `password_hash`. **No salt**. **No iteration**. This is the v1 fix target.

### JWT (intentionally weak)

JJWT, HS256, signed with `app.jwt.secret`. Claims: `sub` (user id), `email`. **No `exp` claim.** Token is valid forever until the secret rotates. This is the v1 fix target.

### Tests

JUnit 5 — happy path only:

1. `signup_thenLogin_thenMe_succeeds`
2. `signup_withDuplicateEmail_returns409`
3. `login_withWrongPassword_returns401`
4. `me_withoutToken_returns401`

Use `@SpringBootTest` with `@AutoConfigureMockMvc`; no Testcontainers yet (introduced in v2 if needed).

## Intentional weaknesses (each fixed in a later version)

| Weakness | Why it's bad | Fixed in |
|---|---|---|
| SHA-256 unsalted hashing | Rainbow-table-vulnerable; fast = brute-forceable | v1 |
| No input validation | Any string accepted as email; empty passwords pass | v1 |
| No rate limit on `/login` | Online brute force trivial | v1 |
| JWT has no `exp` claim | Stolen token = lifetime access | v1 |
| No refresh token / no logout | No credential rotation possible | v1 |
| HikariCP default pool (10) | Bottleneck above ~30 concurrent requests | v2 |
| No explicit email index tuning | Documented but not optimized | v2 |
| `System.out.println` logs | No structure, no correlation IDs | v5 |
| No metrics / no traces | Operationally blind | v5 |
| Login error distinguishes "no such email" vs "wrong password" | Account enumeration | v6 |

## What v0 does NOT add

Everything not listed in "What v0 builds." Specifically: bcrypt, validation, rate limiting, token expiry, refresh tokens, OAuth, MFA, observability, password reset, email verification, lockout, audit. Each has its own version.

## Done criteria

1. `./gradlew :services:identity:v0-naive:check` passes
2. `docker compose -f infra/compose/docker-compose.yml -f infra/compose/overlays/identity-v0.yml up -d` brings the service healthy on port 8101
3. The following curl flow works end-to-end:
   ```bash
   curl -X POST localhost:8101/signup -H 'Content-Type: application/json' \
     -d '{"email":"test@example.com","password":"hunter2"}'
   # → 201 {"id":1,"email":"test@example.com"}

   TOKEN=$(curl -s -X POST localhost:8101/login -H 'Content-Type: application/json' \
     -d '{"email":"test@example.com","password":"hunter2"}' | jq -r .token)

   curl localhost:8101/me -H "Authorization: Bearer $TOKEN"
   # → 200 {"id":1,"email":"test@example.com"}
   ```
4. `services/identity/v0-naive/DESIGN.md` exists and contains the "Intentional weaknesses" table verbatim
5. `services/identity/v0-naive/README.md` exists with the curl examples above and a "how to run" section

## Compose overlay

`infra/compose/overlays/identity-v0.yml`:

```yaml
services:
  identity-v0:
    build:
      context: ../../../
      dockerfile: services/identity/v0-naive/Dockerfile
    image: identity-v0:local
    ports:
      - "8101:8101"
    environment:
      DB_HOST: postgres
      DB_USER: postgres
      DB_PASSWORD: postgres
      JWT_SECRET: dev-only-secret-please-change-this-is-at-least-32-bytes
    depends_on:
      postgres:
        condition: service_healthy
```

(Assumes a base `docker-compose.yml` defines the `postgres` service with `identity_v0` database created at startup. The base compose file is owned by main and provides the shared infra.)

## Claude Code prompt (paste this into Claude Code in the service/identity worktree)

```
Build identity v0-naive.

Read service-plans-v2/identity/v0-naive.md for the complete spec and service-plans-v2/identity/README.md for service-wide context. Read also docs/adr/0001-versions-coexist-and-vertical-first-build.md to understand the per-version module layout (assume Round 0 has already restructured the repo).

Create services/identity/v0-naive/ as a new Gradle module containing:
- build.gradle.kts with exactly the dependencies listed in the spec
- src/main/resources/application.yml with the configuration shown in the spec
- src/main/resources/db/migration/V1__init.sql with the users table per the spec
- src/main/java with the three endpoints (signup, login, me) using JPA entities, a SHA-256 password hashing component (deliberately weak, no salt), and a JJWT 0.12 token issuer (HS256, NO exp claim)
- A Dockerfile that builds the Spring Boot fat jar and runs it on port 8101
- src/test/java with the four JUnit tests listed in the spec
- DESIGN.md containing the "Intentional weaknesses" table from the spec verbatim
- README.md with the curl examples from the spec and run instructions

Create infra/compose/overlays/identity-v0.yml with the contents shown in the spec.

Do NOT add bcrypt, validation, rate limiting, token expiry, indexes beyond what the spec lists, structured logging, metrics, or anything else from later versions. The intentional weaknesses must be present and documented.

Do NOT modify any other service's code or any other version of identity. Do NOT modify settings.gradle.kts (it discovers new modules dynamically per ADR-0001). Do NOT run git commit.

When the done criteria in the spec are met, stop.
```
