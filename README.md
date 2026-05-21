# backend-core

Reusable backend foundation for SaaS-style products and AI-powered services,
built as a multi-version learning platform. Nine services and three shared
modules each evolve through a sequence of intentionally distinct
implementations, so any two versions can be run side-by-side and the diff
between them is a first-class teaching artifact.

## Project shape

- **Nine services**: identity, organization, authorization, notification,
  file-storage, integration, usage-metering, billing, payment.
- **Three shared modules with versions**: `pkg/idempotency`, `pkg/audit`,
  `infra/observability`.
- **Three single-version helpers**: `pkg/errors`, `pkg/httpx`,
  `pkg/observability-lib`.
- **One React frontend**: `ui/frontend/` (a version selector lets it point at
  any built service-version).

Each service version lives in its own Gradle module at
`services/<svc>/v<N>-<name>/`, runs on its own port, owns its own Postgres
database, and ships with its own `docker-compose` overlay. Earlier versions
are never modified.

## Repository layout

```
backend-core/
├── README.md, CONTRIBUTING.md
├── MASTER-PLAN-V2.md          ← top-level blueprint
├── PARALLEL-WORKFLOW.md       ← branch / worktree / tmux orchestration
├── SETUP-INITIAL.md           ← one-time bootstrap prompt
├── settings.gradle.kts        ← dynamic module discovery
├── build.gradle.kts           ← Java 21 toolchain, Maven Central
├── gradlew, gradle/wrapper/
├── docs/
│   ├── adr/                   ← architecture decision records
│   ├── comparisons/           ← per-version-pair reverse-engineering notes
│   └── runbooks/              ← (filled in once observability v4 lands)
├── service-plans-v2/          ← per-version build specs
│   ├── identity/ ...          ← v0-naive.md … v6-hardened.md
│   └── ...
├── services/
│   ├── identity/v0-naive/ ... v6-hardened/
│   └── ...
├── pkg/
│   ├── idempotency/v0/ ... v3/
│   ├── audit/v0/ ... v4/
│   ├── errors/, httpx/, observability-lib/
├── infra/
│   ├── compose/
│   │   ├── docker-compose.yml      ← base (Postgres)
│   │   └── overlays/               ← one file per service-version
│   └── observability/v0/ ... v4/
├── ui/frontend/
└── load-tests/
```

## Quick start

1. **Bootstrap (already done if you can read this past the placeholder
   commit):** see `SETUP-INITIAL.md`.
2. **Set up branches, worktrees, and tmux sessions:** see
   `PARALLEL-WORKFLOW.md` → "One-time setup".
3. **Build a service version:** open the relevant worktree's tmux session and
   paste the "Claude Code prompt" block from
   `service-plans-v2/<svc>/v<N>-*.md` into Claude Code.
4. **Run a service version locally:**

   ```bash
   docker compose -f infra/compose/docker-compose.yml \
                  -f infra/compose/overlays/<svc>-v<N>.yml up
   ```

## Status

Repository skeleton bootstrapped per `SETUP-INITIAL.md`. No service modules
filled in yet; each `services/<svc>/v<N>-*/` directory contains only a
`.gitkeep`. Identity is the canonical first build (`service-plans-v2/identity/`
plans are refined and build-ready).

## Further reading

- [`MASTER-PLAN-V2.md`](MASTER-PLAN-V2.md) — services, version counts, port
  ranges, evolution model
- [`PARALLEL-WORKFLOW.md`](PARALLEL-WORKFLOW.md) — multi-branch / multi-worktree
  workflow, coordination contract, dynamic-discovery settings file
- [`docs/adr/`](docs/adr/) — architecture decision records
  - [`0001-versions-coexist-and-vertical-first-build.md`](docs/adr/0001-versions-coexist-and-vertical-first-build.md)
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — branch model, commit format, ADR
  process
