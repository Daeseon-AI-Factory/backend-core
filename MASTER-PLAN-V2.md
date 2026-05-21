# Master Plan — `backend-core`

Top-level blueprint for the backend platform. Everything else (per-service plans, parallel workflow, initial setup) refers to this document.

---

## What this is

A monorepo containing nine backend services, three shared modules with versions, an infra-observability bundle, and a frontend UI — all designed so each service evolves through *multiple coexisting versions* (v0 → v_final). Each version is its own Gradle module, runs on its own port, owns its own Postgres database, and ships with its own docker-compose overlay.

Goals:
- **Real product.** Builds a usable backend platform.
- **Learning artifact.** Each version exposes one or two specific engineering decisions; reading the diff between v(N) and v(N+1) teaches a real skill.
- **Interview portfolio.** Each transition has a defensible "this is why we did it" story backed by code + DESIGN.md + (where relevant) load test numbers.

This is not a tutorial. It is a real platform written in the slow, layered way a senior engineer would walk a junior through it.

---

## Services

| # | Service | Versions | Port range | Purpose |
|---|---|---|---|---|
| 1 | **identity** | v0–v6 (7) | 8101–8107 | Authentication, sessions, OAuth, MFA, hardening |
| 2 | **organization** | v0–v4 (5) | 8201–8205 | Workspaces, roles, invitations, multi-org, SSO |
| 3 | **authorization** | v0–v4 (5) | 8301–8305 | RBAC → ABAC → cached distributed policy engine |
| 4 | **notification** | v0–v5 (6) | 8401–8406 | sync → async → broker → outbox → multichannel → production |
| 5 | **file-storage** | v0–v4 (5) | 8501–8505 | local → S3 → presigned → multipart → CDN |
| 6 | **integration** | v0–v4 (5) | 8601–8605 | Outbound webhooks → signed → inbound → OAuth connectors → dashboard |
| 7 | **usage-metering** | v0–v4 (5) | 8701–8705 | Events → rollups → quotas → streaming → pre-aggregated |
| 8 | **billing** | v0–v5 (6) | 8801–8806 | Plans → subscriptions → prorations → invoices → tax → dunning |
| 9 | **payment** | v0–v5 (6) | 8901–8906 | Mock → Stripe hosted → API → webhooks → refunds → fraud |

Plus shared modules:
- **`pkg/idempotency`** (v0–v3) — request deduplication library
- **`pkg/audit`** (v0–v4) — append-only audit event store
- **`infra/observability`** (v0–v4) — Prometheus, Loki, Tempo, Alertmanager stack

Plus a single-version `ui/frontend/` React app (a version selector lets the user point its forms at any built service-version).

**Plan completeness status:**
- Identity plans: refined, build-ready
- Organization, authorization, notification, file-storage, integration, usage-metering plans: drafts (will likely need adjustment during build)
- Billing, payment, shared modules, observability: plans not yet written

---

## Evolution model

Each version of each service lives in its own folder: `services/<svc>/v<N>-<name>/` (or `pkg/<mod>/v<N>/` for shared modules). The folder is a complete, independent Gradle module:

- Own `build.gradle.kts`
- Own `src/main/java/` and `src/test/java/`
- Own Flyway migrations
- Own `DESIGN.md` (what's intentional, what's deferred, what fails)
- Own `README.md` (curl examples, run instructions)

A new version is built by *reading* the previous version's source as reference and *re-implementing* the relevant parts in a fresh module. The old code is never modified — earlier versions remain runnable as historical references.

Each version gets a unique port and a unique Postgres database, so any two versions can run side-by-side for direct comparison.

This is documented formally in **ADR-0001** (created by Initial Setup).

---

## Tech stack baseline

- **Language:** Java 21
- **Framework:** Spring Boot 3.x — root project pins the exact version
- **Build:** Gradle Kotlin DSL with the Gradle wrapper
- **Database:** Postgres 17 (TimescaleDB extension for usage-metering v3+)
- **Migrations:** Flyway
- **Broker:** RabbitMQ (notification v2+), Kafka (usage-metering v3+)
- **Cache:** Redis (authorization v4+, notification v5, usage-metering v2+)
- **Object storage:** MinIO (S3-compatible) for local dev
- **Testing:** JUnit 5, Mockito, Testcontainers, k6 for load
- **Observability:** Spring Boot Actuator + Micrometer + Prometheus + Loki + Tempo + OpenTelemetry
- **Containers:** Docker + docker-compose
- **CI:** GitHub Actions

Exact library coordinates and versions for individual modules are pinned in the per-version files under `service-plans-v2/`.

---

## Repository layout (after Initial Setup runs)

```
backend-core/
├── README.md
├── CONTRIBUTING.md
├── MASTER-PLAN-V2.md          ← this file
├── PARALLEL-WORKFLOW.md       ← orchestration
├── SETUP-INITIAL.md           ← one-time bootstrap prompt
├── settings.gradle.kts        ← dynamically discovers all service-version modules
├── build.gradle.kts
├── gradle/wrapper/            ← Gradle wrapper
├── gradlew, gradlew.bat
├── .gitignore, .editorconfig
├── .github/workflows/check.yml
├── docs/
│   ├── adr/
│   │   ├── 0000-template.md
│   │   └── 0001-versions-coexist-and-vertical-first-build.md
│   ├── comparisons/           ← reverse-engineering notes per version pair
│   └── runbooks/              ← created when observability v4 lands
├── service-plans-v2/          ← per-version build specs (read by Claude Code)
│   ├── identity/
│   │   ├── README.md
│   │   ├── v0-naive.md
│   │   └── ... v6-hardened.md
│   ├── organization/
│   └── ... (one folder per service)
├── services/
│   ├── identity/
│   │   ├── v0-naive/          ← a Gradle module (empty .gitkeep at start)
│   │   ├── v1-security/
│   │   └── ...
│   ├── organization/
│   └── ... (one folder per service)
├── pkg/
│   ├── idempotency/v0/ v1/ v2/ v3/
│   ├── audit/v0/ v1/ v2/ v3/ v4/
│   ├── errors/                ← single-version
│   ├── httpx/                 ← single-version
│   └── observability-lib/     ← single-version
├── infra/
│   ├── compose/
│   │   ├── docker-compose.yml ← base (postgres, redis as services need it)
│   │   └── overlays/          ← one file per service-version
│   └── observability/v0/ … v4/
├── ui/
│   └── frontend/              ← React app, single version
└── load-tests/
    └── <service>-v<N>/        ← k6 scripts per version
```

---

## Build sequence

1. **Initial Setup** — bootstrap the repo to the layout above. Single Claude Code prompt. See `SETUP-INITIAL.md`.
2. **Build rounds** — each service evolves through its versions in its own git worktree on its own branch. Shared modules (`pkg/`, `infra/observability/`) are built on `main` as services need them. See `PARALLEL-WORKFLOW.md`.
3. **Integration** — once a service is built up to v_final on its branch, merge to main. Other services that depend on it can rebase.
4. **UI catch-up** — `ui/frontend/` is built alongside but lags by a few rounds; the version selector picks up new services as they appear.

---

## Coordination contract (summary; full version in PARALLEL-WORKFLOW.md)

| File / directory | Owned by |
|---|---|
| `services/<svc>/v*/` | `service/<svc>` branch only |
| `infra/compose/overlays/<svc>-v*.yml` | `service/<svc>` branch only |
| `pkg/*` | `main` only |
| `infra/compose/docker-compose.yml` (base) | `main` only |
| `infra/observability/` | `main` only |
| `settings.gradle.kts`, root `build.gradle.kts` | `main` only |
| `README.md`, `docs/adr/`, `MASTER-PLAN-V2.md` | `main` only |
| `ui/frontend/` | `service/ui` branch only |

The trick: root `settings.gradle.kts` discovers modules dynamically by walking `services/*/v*/`. Service branches add their module by creating its folder; no edit to root needed. No merge conflict.

---

## Quality posture

This is a learning + portfolio project, not a contracted production deployment.

- The architectural progressions (RBAC→ABAC, sync→broker→outbox, local→S3→CDN, etc.) are textbook and defensible
- Specific library versions and minor SQL details may need adjustment during build
- Identity is the canonical reference — most polished
- Other services are drafts: expect to refine specs as Claude Code surfaces issues during build

When in doubt: build the simplest defensible version, document the gap in DESIGN.md, move on. Iterate when there's information.
