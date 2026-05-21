# Phase 0 — Repository Skeleton

> Paste this entire file as the first task in Claude Code, after creating an empty git repository with `README.md` already committed at the root.

---

## Context

This is the first real commit to `backend-platform-core`. Read `README.md` at the repo root before doing anything else — it contains the blueprint, the evolution model, the phase roadmap, and the rules about what lives in `services/` versus `docs/evolution/`. Do not violate those rules.

The repository is currently empty except for `README.md` and this prompt.

## Goal

Build the empty multi-module skeleton. No service code yet. No business logic. No Spring Boot applications. Just the bones the next phases will fill in.

The end state of this phase is: a developer can clone the repo, run `./gradlew check` and `docker compose up`, and both succeed without doing anything else.

## What to build

### 1. Gradle multi-module setup
- `settings.gradle.kts` at the root that includes the `pkg:*` subprojects
- Root `build.gradle.kts` with shared plugins (`java`, `jacoco`) and a Java 21 toolchain
- Use Gradle Kotlin DSL throughout, not Groovy
- Pin a Gradle wrapper version

### 2. `pkg/` shared library skeleton
Create the following modules, each with its own `build.gradle.kts` and a single empty package directory under `src/main/java/`. No real Java code — these are placeholders that the multi-module build can see.

- `pkg/observability/` — will hold metrics and logging helpers (Phase 2 fills it)
- `pkg/errors/` — will hold common error types
- `pkg/idempotency/` — will hold the idempotency middleware
- `pkg/audit/` — will hold the audit event emitter
- `pkg/httpx/` — will hold HTTP client and server helpers

Each module's `build.gradle.kts` declares only the Java plugin and JUnit 5 test dependencies. No Spring dependencies yet.

### 3. Docker Compose for local infrastructure
- `infra/compose/docker-compose.yml`
- Postgres 16 service, port 5432
- Use a `.env.example` at the repo root listing the variables (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB)
- Add a healthcheck on the Postgres service using `pg_isready`
- Add a named volume for Postgres data

### 4. GitHub Actions CI
- `.github/workflows/check.yml`
- Triggers on pull request and push to main
- Sets up JDK 21 (Temurin)
- Caches Gradle's home directory
- Runs `./gradlew check`

### 5. Documentation structure
- `docs/adr/0000-template.md` — the ADR template, matching the format in `README.md` (Context / Decision / Alternatives / Trade-offs / Revisit when)
- `docs/adr/0001-monorepo-and-evolution-model.md` — the first real ADR, written in plain English with no buzzwords. It documents why this repository chose a monorepo and the version-folder evolution model. Reference the relevant section of `README.md`.
- `docs/evolution/.gitkeep`
- `docs/runbooks/.gitkeep`

### 6. Top-level files
- `.gitignore` — Java, Gradle, IntelliJ/VS Code, `.env`
- `.editorconfig` — 4-space Java indent, LF line endings, UTF-8
- `CONTRIBUTING.md` — short, plain-English document covering:
  - How to add a new service module
  - How to write an ADR (referencing the template)
  - How to add a new version folder under `docs/evolution/<service>/`
  - How to run benchmarks once they exist
- `load-tests/.gitkeep`

## What NOT to do

These items belong to later phases. Do not preemptively add them, even if it seems efficient.

- **No Spring Boot applications.** No `services/` modules at all in this phase.
- **No real Java code** beyond empty package directories needed for Gradle to recognise the modules.
- **No Kubernetes manifests.** k8s comes later, only when Docker Compose has become insufficient and that pain has been documented.
- **No Prometheus, Grafana, Loki, or OpenTelemetry** in docker-compose. Those arrive in Phase 2.
- **No secrets manager.** `.env.example` is the entire secrets story for now.
- **No pre-commit hooks, no dependency-update bots, no code-quality bots.** Those add cognitive load and obscure the learning. They get justified later if at all.
- **No JaCoCo HTML report uploads.** JaCoCo plugin is enough; report viewing happens locally.
- **Do not add any dependency I did not name above.** If something seems missing, stop and ask before adding.

## Done when

All five conditions hold:

1. `./gradlew check` runs locally and passes (it will be near-empty — that is correct)
2. `docker compose -f infra/compose/docker-compose.yml up -d` brings up Postgres and the healthcheck reports healthy within 30 seconds
3. The GitHub Actions workflow runs green on the first push (verified by the user manually)
4. Both ADR files exist and are readable
5. `tree` of the repo matches the layout shown in `README.md`, with `services/` directory existing but empty except for a `.gitkeep`

## Deliverables alongside the code

- A single commit (or a small number of focused commits) implementing this phase
- A short commit message describing what Phase 0 produced
- Do not write any ADRs beyond the two specified above
- Do not modify `README.md` — it is the contract for this phase

## After this phase

Once these five done-conditions hold, stop. Wait for the next phase prompt (`PHASE-1-IDENTITY-V0-PROMPT.md`) before adding any service code.
