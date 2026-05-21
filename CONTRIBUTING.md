# Contributing

This repository builds nine services in parallel across multiple branches.
The conventions below exist so that parallel work does not collide.

## Branch model

- **`main`** holds shared infrastructure: `pkg/`, `infra/compose/docker-compose.yml`
  (base), `infra/observability/`, `settings.gradle.kts`, root `build.gradle.kts`,
  `README.md`, `docs/adr/`, `MASTER-PLAN-V2.md`, and the planning documents
  under `service-plans-v2/`.
- **`service/<svc>`** per service (`service/identity`, `service/notification`,
  etc.). Each branch only modifies its own service folder
  (`services/<svc>/v*/`) and its own compose overlay
  (`infra/compose/overlays/<svc>-v*.yml`).
- **`service/ui`** for the React frontend at `ui/frontend/`.

A new version of a service is built on its branch by adding a new
`services/<svc>/v<N>-<name>/` directory. The root `settings.gradle.kts`
discovers modules dynamically — there is no need to edit root files when
adding a version. This is by design and removes the most common source of
merge conflicts. See `PARALLEL-WORKFLOW.md` for the full coordination
contract, the worktree + tmux setup, and the rebase rhythm.

## The "do not edit earlier versions" rule

Once a service version is committed (for example, `services/identity/v0-naive/`
on `service/identity`), that directory is a historical artifact. **Do not
modify it.** New behavior, fixes, or improvements belong in the next
version directory (`services/identity/v1-security/`, etc.).

This rule is what makes the per-version diff a teaching artifact: a reader
can `diff -r services/identity/v0-naive/ services/identity/v1-security/` and
see exactly what changed between two intentional designs. If older versions
silently drift, the diff stops being meaningful.

Exceptions are limited to *cosmetic* changes that do not alter runtime
behavior — typo fixes in comments, doc clarifications. If you are tempted to
make a non-cosmetic change to an older version, surface it as a follow-up
ADR or a new version instead.

## Commit messages

Format: `<service> v<N>-<name>: <description>`.

Examples:

```
identity v0-naive: scaffold module, /health, in-memory user store
notification v3-outbox: outbox table + scheduled poller + idempotency keys
pkg/idempotency v0: DB-backed idempotency filter
```

For changes outside any service (root build files, ADRs, planning docs), drop
the prefix and use a plain imperative subject:

```
docs: add ADR-0005 on Redis cache topology for authorization v4
infra/compose: bump postgres to 17.2-alpine
```

Keep the subject under ~70 characters. Use the body for the *why*, not the
*what* — the diff already shows what changed.

## The role of MASTER-PLAN-V2.md and `service-plans-v2/`

- **`MASTER-PLAN-V2.md`** is the top-level blueprint: services, version
  counts, ports, evolution model, tech stack. Changes to it land on `main`
  via PR.
- **`service-plans-v2/<svc>/v<N>-<name>.md`** is the per-version build spec
  read by Claude Code when constructing that version. Each spec contains a
  copy-pasteable "Claude Code prompt" block. Refine specs on `main` before
  the matching service branch starts that version.

Treat the plans as living documents: when a build surfaces an issue, fix the
plan on `main` first, then continue on the service branch.

## Adding an ADR

1. Pick the next free number under `docs/adr/`.
2. Copy `docs/adr/0000-template.md` to `docs/adr/NNNN-<kebab-title>.md`.
3. Fill in Status, Context, Decision, Consequences, References.
4. Open a PR to `main`. Service branches rebase to pick it up.

If a new ADR supersedes an older one, mark the older ADR's status as
*Superseded by ADR-NNNN* and link both ways.

## Running checks locally

```bash
./gradlew check
docker compose -f infra/compose/docker-compose.yml config
```

CI (`.github/workflows/check.yml`) runs `./gradlew check` on every push to
`main` and every PR.
