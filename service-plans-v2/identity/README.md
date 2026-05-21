# Identity Service — Overview

This file is for humans, not for Claude Code build prompts. The per-version files (`v0-naive.md` … `v6-hardened.md`) are the build inputs.

## Service purpose

Identity owns "who is this user?" — registration, authentication, sessions, OAuth, MFA, and operational hardening. Every other backend service depends on identity for user resolution via HTTP.

## Version map

| v | Name | Headline change | Port | DB |
|---|---|---|---|---|
| 0 | naive | Bare signup/login/me with intentional weaknesses | 8101 | `identity_v0` |
| 1 | security | bcrypt, Bean Validation, Bucket4j rate limit, JWT exp, refresh tokens | 8102 | `identity_v1` |
| 2 | performance | Indexes, HikariCP tuning, login short-circuit | 8103 | `identity_v2` |
| 3 | oauth | Google + GitHub OAuth2 client, account linking | 8104 | `identity_v3` |
| 4 | mfa | TOTP enrollment, recovery codes, device tracking | 8105 | `identity_v4` |
| 5 | observability | Micrometer/Prometheus, JSON logs, OpenTelemetry traces | 8106 | `identity_v5` |
| 6 | hardened | Account lockout, enumeration prevention, password reset, email verify, audit emission, geo signal | 8107 | `identity_v6` |

## Why these transitions (each fixes the previous)

| Transition | What v(N-1) fails at |
|---|---|
| v0 → v1 | OWASP self-audit: SHA-256 hashing, no validation, no rate limit, JWTs valid forever |
| v1 → v2 | k6 load test shows p99 spike: seq scan on email lookup, undersized HikariCP pool |
| v2 → v3 | Password-only friction; real users want "Sign in with Google/GitHub" |
| v3 → v4 | Stolen passwords still compromise accounts; need a phishing-resistant second factor |
| v4 → v5 | Plain `System.out` logs; no metrics; no traces — operationally blind |
| v5 → v6 | Known attack surface: enumeration, brute force across IPs, no password reset, no email verification, no audit trail |

## How each version is built

1. In the `service/identity` git worktree, open a tmux session.
2. Launch Claude Code: `claude --permission-mode acceptEdits`.
3. Copy the "Claude Code prompt" block from the relevant `vN-name.md` file as your first message.
4. Wait for the version to be complete and the done criteria to pass.
5. You commit and push manually.
6. Move to the next version's file.

Each version is a separate Gradle module under `services/identity/vN-name/`. Earlier versions are never modified — they remain runnable as historical references.

## Reverse-engineering workflow

After multiple versions exist, for each adjacent pair `(v(N-1), v(N))`:

```bash
diff -ru services/identity/v(N-1)-*/src services/identity/vN-*/src | less
```

Read both module READMEs and DESIGN.md files side by side. Run both versions concurrently (different ports), trigger the failure mode of v(N-1), confirm v(N) handles it.

Optionally write a comparison note to `docs/comparisons/identity-v(N-1)-to-vN.md`.

## Port reservations

```
8101  v0-naive
8102  v1-security
8103  v2-performance
8104  v3-oauth
8105  v4-mfa
8106  v5-observability
8107  v6-hardened
```

## Database reservations

Single Postgres container, one logical database per version: `identity_v0` … `identity_v6`. Each module's Flyway migrations operate only on its own DB.

## Local-dev quick reference

```bash
# Bring up just one version
docker compose -f infra/compose/docker-compose.yml \
  -f infra/compose/overlays/identity-v0.yml up -d

# Health check
curl http://localhost:8101/actuator/health    # v5+ ; for v0-v4 use a custom endpoint or root
```

## When to stop

v6 is the final planned version. Future directions outside the scope of this learning track:
- WebAuthn / passkeys (would naturally be v7)
- Account merging across providers
- Hardware security module (HSM) for key storage
- Regulatory compliance: GDPR/CCPA data export, right to erasure with retention

Adding v7+ follows the same per-version-file pattern.
