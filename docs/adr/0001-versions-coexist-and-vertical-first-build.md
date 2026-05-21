# ADR-0001: Versions coexist as Gradle modules; vertical build per service

## Status

Accepted

## Context

`backend-core` is a multi-version learning platform. Each backend service
evolves through a sequence of intentionally distinct implementations (for
example, identity v0 → v6, notification v0 → v5). The point of the project is
not the final state of any service but the **diff between consecutive
versions** — the reasoning, trade-off, and code change that takes v(N-1) to
v(N).

This puts two requirements on the repository structure:

1. **Any two versions must be runnable side-by-side** so a reader can hit
   `localhost:8101` (identity v0) and `localhost:8102` (identity v1) and
   directly compare behavior, performance, and failure modes.
2. **Parallel construction** is desirable: different services build on their
   own branches, in their own git worktrees, with their own tmux sessions, so
   that work on `identity` does not block work on `notification`. See
   `PARALLEL-WORKFLOW.md`.

Several layout strategies were considered:

- *Single module per service, branches per version.* Rejected: only one
  version is checked out at a time; side-by-side comparison requires juggling
  branches, and the per-version diff disappears into git history.
- *Single module per service, in-place rewrites with tags marking versions.*
  Rejected for the same reason — historical versions are not runnable
  artifacts without a checkout.
- *Coexisting per-version modules under `services/<svc>/v<N>-<name>/`.*
  Selected.

## Decision

All versions of all services and shared modules live concurrently as Gradle
sub-modules.

- A service version lives at `services/<svc>/v<N>-<name>/` (for example,
  `services/identity/v3-oauth/`).
- A shared module version lives at `pkg/<mod>/v<N>/` (or, for
  single-version modules, just `pkg/<mod>/`).
- Each version directory is a complete, independent Gradle module with its
  own `build.gradle.kts`, its own `src/`, its own Flyway migrations, its own
  `DESIGN.md`, and its own `README.md`.
- Each version is assigned a unique HTTP port and a unique Postgres database
  (per `MASTER-PLAN-V2.md`), so any two versions can run simultaneously.
- **Earlier versions are never modified.** A new version is built by *reading*
  the previous version's source as reference and *re-implementing* in a fresh
  module. Once `v0` is committed, it is a historical artifact.
- Module discovery is dynamic: the root `settings.gradle.kts` walks
  `services/*/v*/` and `pkg/*/v*/` at configuration time. A service branch
  creates its module directory and the root build picks it up — no edit to
  root files, no merge conflict on `settings.gradle.kts`.

## Consequences

**Positive**

- Side-by-side runtime comparison is trivial: bring up the two compose
  overlays, point a load test at both, observe.
- The diff between `v(N-1)` and `v(N)` is a first-class teaching artifact:
  reviewers can `diff -r services/identity/v0-naive/ services/identity/v1-security/`
  and see exactly what changed and why.
- Parallel construction works because each service-version directory is owned
  by exactly one branch; the dynamic-discovery `settings.gradle.kts` means
  branches never touch root files.
- The "what changed" story for each version is a real PR with a real diff,
  not a description of past work.

**Negative / accepted trade-offs**

- The repository is large: at completion, roughly fifty Gradle modules.
- Configuration time and disk usage are higher than a normal single-module
  service. Mitigations: Gradle parallel/configure-on-demand, sparse local
  builds (`./gradlew :services:identity:v0-naive:build`), per-worktree Gradle
  caches.
- Some code duplication across versions is intentional — the duplication is
  the point. Refactoring shared logic into `pkg/` is acceptable only when the
  abstraction is itself a teaching artifact (idempotency, audit,
  observability).

**Neutral / follow-ups**

- Compose overlays per version live under `infra/compose/overlays/` and are
  owned by the matching service branch. Future ADRs may define the overlay
  schema if cross-version drift becomes a problem.
- Shared `pkg/` modules introduce ordering constraints documented in
  `PARALLEL-WORKFLOW.md` ("Order matters for cross-cuts").

## References

- `MASTER-PLAN-V2.md` — services, version counts, port ranges
- `PARALLEL-WORKFLOW.md` — branch / worktree / tmux orchestration and the
  dynamic-discovery `settings.gradle.kts` snippet
- `SETUP-INITIAL.md` — bootstrap procedure that materializes the layout
