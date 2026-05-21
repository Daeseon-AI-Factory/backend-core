# Backend Platform Core

A backend platform built one phase at a time. Every change must be justified by a measurement or a reproduced failure. The repository history is the learning artifact.

---

## What this is

A single repository that will hold the backend services for my own products. Each service evolves through numbered versions — v0 is intentionally naive, and every later version fixes a specific class of problem with documented before-and-after numbers.

The repository serves two purposes at once:

1. The real platform my products will run on
2. A learning artifact that shows engineering judgment, not just feature completion

If both are not satisfied at every step, the step was wasted.

---

## The services

Nine real services. Each gets its own v0 → vN evolution under `docs/evolution/`.

| # | Service | One-line purpose |
|---|---|---|
| 1 | identity | Who is the user |
| 2 | organization | Workspaces, teams, membership |
| 3 | authorization | What a user is allowed to do (starts as a library inside identity, extracts later) |
| 4 | notification | Email, SMS, push, in-app messages |
| 5 | file-storage | Uploads, downloads, presigned URLs |
| 6 | integration | Webhooks out, third-party connectors in |
| 7 | usage-metering | What the user consumed, used by billing |
| 8 | billing | Subscriptions, invoices, plans |
| 9 | payment | Money in, via a payment provider |

Three shared modules — **not** standalone services. They live in `pkg/` and are imported by services that need them.

| Module | Why it is not a service |
|---|---|
| idempotency | It is a middleware/library every service applies to its write endpoints |
| audit | It is a library that emits events plus an append-only event store, not a request-serving service |
| observability | It is infrastructure — Prometheus, Grafana, OpenTelemetry, log aggregation — not a service the app calls |

These shared modules also have their own v0 → vN evolution. Their progression lives in `docs/evolution/` like the services.

---

## Repository layout

```
backend-platform-core/
├── services/                 always the latest safe version of each service
│   └── identity/             (filled in starting Phase 1)
├── pkg/                      shared libraries imported by services
│   ├── observability/
│   ├── errors/
│   ├── idempotency/
│   ├── audit/
│   └── httpx/
├── infra/
│   ├── compose/              local development infra (Postgres, Redis, Prom, Grafana)
│   └── k8s/                  added much later, only when justified
├── load-tests/               k6 scenarios
├── docs/
│   ├── adr/                  one page per decision
│   ├── runbooks/             how to recover when things break
│   └── evolution/            versioned history per service or module
│       └── identity/
│           ├── README.md
│           ├── v0-naive/
│           │   ├── DESIGN.md
│           │   ├── snapshots/
│           │   ├── benchmark.md
│           │   └── adr/
│           ├── v1-security/
│           └── v2-performance/
├── .github/workflows/        CI
├── README.md                 this file
└── CONTRIBUTING.md           how to add a service, write an ADR, run benchmarks
```

The code under `services/` and `pkg/` is always the latest safe version. The folders under `docs/evolution/` are read-only history — snapshots, design notes, benchmarks for each version.

**Public repository rule:** vulnerable code never lives in `services/`. If v0 of a service has a deliberate weakness for learning, that weakness exists only in the v0 snapshot folder, clearly marked. The live service tree is always safe to read.

---

## Two disciplines that everything follows

### Discipline 1 — ADR for every meaningful decision

Every decision that affects more than one file gets one page in `docs/adr/`. Format:

- **Context** — what is the situation, what numbers do we have
- **Decision** — what we chose
- **Alternatives** — what we considered and rejected, and why
- **Trade-offs** — what we give up by choosing this
- **Revisit when** — the measurable trigger that means we should reopen this

ADRs are written in plain English. No buzzwords. If a reader new to backend cannot follow the reasoning, rewrite the ADR until they can.

### Discipline 2 — Measurement before features

No optimization ships without a before-and-after benchmark. No new feature ships without at least one metric that proves it works. Every service has a `benchmark.md` in its evolution folder.

Three commitments:

1. Observability infrastructure is built before the second feature, not after the tenth bug
2. Every v0 → v1 transition includes a measured comparison
3. "It feels faster" is not an acceptable claim

---

## Evolution model

Each service evolves through numbered versions. The boundaries between versions are not arbitrary — each version solves a specific problem made visible in the previous version's benchmark or failure.

For each version of each service:

- `DESIGN.md` — what this version does well, and what is intentionally weak. Weaknesses are listed so the next version's improvements are obvious.
- `snapshots/` — copies of the key files at this version. Not the whole codebase, just the files that materially changed.
- `benchmark.md` — k6 results: p50, p95, p99, error rate, RPS at the breaking point.
- `adr/` — decisions specific to this version.

The pattern: every later version reads the previous version's `DESIGN.md` to know what to fix, and produces its own `benchmark.md` to prove the fix worked.

---

## Phase roadmap

The first identity-focused arc:

| Phase | What | Done when |
|---|---|---|
| 0 | Repository skeleton | `./gradlew check` passes, Postgres comes up healthy, CI runs green |
| 1 | identity v0 (intentionally naive) | curl signup → login → /me works, DESIGN.md lists intentional weaknesses |
| 2 | Observability infrastructure | Grafana shows RPS, p99, error rate, DB query time for identity |
| 3 | First load test baseline | benchmark.md captured with k6 numbers and Grafana screenshots |
| 4 | identity v1 (security pass) | bcrypt, validation, rate limit, token expiry; before-and-after benchmark |
| 5 | identity v2 (performance pass) | indexes, connection pool tuned; before-and-after benchmark |
| 6 | Testing maturity | Testcontainers integration tests, mutation testing once |

After Phase 6, the cycle restarts for the next service (organization), then the next (authorization extraction), and so on.

Later phases — sketched, not yet detailed:

- 7+ API gateway, Redis caching, async messaging with outbox, resilience patterns, notification service, file storage, audit log strengthening, billing and payment.

Each later phase is unlocked by the measurement or pain point that justifies it.

---

## Tech baseline

| Concern | Choice |
|---|---|
| Language | Java 21 (LTS) |
| Framework | Spring Boot 3.x |
| Build | Gradle with Kotlin DSL |
| Database | Postgres 16 |
| Migrations | Flyway |
| Unit tests | JUnit 5, Mockito |
| Integration tests | Testcontainers |
| Load tests | k6 |
| Metrics | Micrometer + Prometheus |
| Logs | Logback with JSON encoder |
| Local infra | Docker Compose |
| CI | GitHub Actions |

These are the defaults. Any deviation must be justified in an ADR.

---

## Development commands

Once Phase 0 is complete:

```bash
# Bring up local infrastructure
docker compose -f infra/compose/docker-compose.yml up -d

# Build and test everything
./gradlew check

# Run a specific service (once Phase 1 is done)
./gradlew :services:identity:bootRun
```

---

## Status

**Current phase: 0** — repository skeleton.

The next commit creates the multi-module Gradle structure, the pkg/ shared library skeleton, the Docker Compose for Postgres, the CI workflow, the ADR template, and the first real ADR explaining why this repository uses a monorepo and the version-folder evolution model.

See `PHASE-0-PROMPT.md` for the exact instructions used to build the skeleton.
