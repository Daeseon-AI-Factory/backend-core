# Initial Setup — One-shot Bootstrap Prompt

This file produces a single Claude Code prompt that bootstraps the entire `backend-core` repository skeleton from scratch. Run it once on a fresh repo with only `MASTER-PLAN-V2.md`, `PARALLEL-WORKFLOW.md`, `SETUP-INITIAL.md`, and `service-plans-v2/` already in place.

---

## Prerequisites

- Repo cloned or initialized as empty (only `.git/` and possibly a `README.md` from GitHub)
- `MASTER-PLAN-V2.md`, `PARALLEL-WORKFLOW.md`, `SETUP-INITIAL.md` placed at the repo root
- `service-plans-v2/` directory present at the repo root with at least `identity/` populated
- Working tree clean (`git status` shows nothing to commit aside from the three master docs and `service-plans-v2/`)

If your repo currently has any other state from previous attempts, wipe first:

```bash
cd ~/code/backend-core
git checkout main
# Reset to GitHub's initial commit (the one created when you first made the repo)
git reset --hard $(git rev-list --max-parents=0 HEAD)
# Now place the master docs and service-plans-v2 again, then continue
git status   # should show the master docs + service-plans-v2/ as untracked
```

---

## How to use

1. Open Claude Code in the main repo directory:
   ```bash
   cd ~/code/backend-core
   claude --permission-mode acceptEdits
   ```
2. Copy the **entire code block below** (between the triple backticks) and paste it as the first message to Claude Code.
3. Wait for Claude Code to finish. Watch the changes; if anything looks off, interrupt and ask.
4. Manually verify (see "After this prompt completes" below).
5. Commit and push.

---

## The prompt

```
Initial Setup — bootstrap the backend-core repository from scratch

Read MASTER-PLAN-V2.md and PARALLEL-WORKFLOW.md at the repo root before any code changes. These describe the target layout, services, ports, and evolution model.

This is a structural bootstrap. No service code is written. No actual modules are filled in. The output is the complete repository skeleton: Gradle setup, empty version directories, base compose with Postgres, ADRs, README, CI workflow.

==========
TASKS
==========

1. Gradle setup at the repo root:
   - Generate the Gradle wrapper for Gradle 8.x (run `gradle wrapper --gradle-version 8.10` if Gradle is available, otherwise create the wrapper files manually: gradlew, gradlew.bat, gradle/wrapper/gradle-wrapper.jar, gradle/wrapper/gradle-wrapper.properties)
   - Root build.gradle.kts: Kotlin DSL, applies no plugins at root (subprojects bring their own), declares the Java toolchain (Java 21), uses Mavencentral repositories
   - Root settings.gradle.kts: dynamically discovers modules per the snippet in PARALLEL-WORKFLOW.md "The settings.gradle.kts dynamic discovery trick" section. Set rootProject.name = "backend-core".

2. Create empty version directories for all nine services, each with a single .gitkeep file:

   - services/identity/{v0-naive, v1-security, v2-performance, v3-oauth, v4-mfa, v5-observability, v6-hardened}/.gitkeep
   - services/organization/{v0-naive, v1-rbac, v2-invitations, v3-multi-org, v4-sso}/.gitkeep
   - services/authorization/{v0-hardcoded, v1-rbac-db, v2-local-cache, v3-abac, v4-distributed-cache}/.gitkeep
   - services/notification/{v0-sync, v1-async-inproc, v2-broker, v3-outbox, v4-multichannel, v5-production}/.gitkeep
   - services/file-storage/{v0-local, v1-s3, v2-presigned, v3-multipart, v4-cdn}/.gitkeep
   - services/integration/{v0-out, v1-signed, v2-in, v3-oauth-connector, v4-dashboard}/.gitkeep
   - services/usage-metering/{v0-events, v1-rollups, v2-limits, v3-streaming, v4-preaggregated}/.gitkeep
   - services/billing/{v0-hardcoded, v1-subscriptions, v2-prorations, v3-invoices, v4-tax, v5-dunning}/.gitkeep
   - services/payment/{v0-mock, v1-stripe-hosted, v2-stripe-api, v3-webhooks, v4-refunds, v5-fraud}/.gitkeep

3. Create empty version directories for shared modules:
   - pkg/idempotency/{v0, v1, v2, v3}/.gitkeep
   - pkg/audit/{v0, v1, v2, v3, v4}/.gitkeep
   - infra/observability/{v0, v1, v2, v3, v4}/.gitkeep

4. Create single-version pkg module placeholders (just .gitkeep for now; content fills in when something needs them):
   - pkg/errors/.gitkeep
   - pkg/httpx/.gitkeep
   - pkg/observability-lib/.gitkeep

5. Create ui/frontend/.gitkeep (React app placeholder, built later).
6. Create infra/compose/overlays/.gitkeep.
7. Create load-tests/.gitkeep.
8. Create docs/comparisons/.gitkeep and docs/runbooks/.gitkeep.

9. Create infra/compose/docker-compose.yml as the base compose file. It defines a single Postgres service that initializes the per-version databases on startup. The exact content:

```yaml
services:
  postgres:
    image: postgres:17-alpine
    container_name: backend-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: postgres
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init-databases.sh:/docker-entrypoint-initdb.d/init-databases.sh:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  postgres-data:

networks:
  default:
    name: backend-core-net
```

Also create infra/compose/init-databases.sh, executable, that creates all the per-service-version databases on first startup:

```bash
#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  -- identity
  CREATE DATABASE identity_v0; CREATE DATABASE identity_v1; CREATE DATABASE identity_v2;
  CREATE DATABASE identity_v3; CREATE DATABASE identity_v4; CREATE DATABASE identity_v5;
  CREATE DATABASE identity_v6;
  -- organization
  CREATE DATABASE organization_v0; CREATE DATABASE organization_v1; CREATE DATABASE organization_v2;
  CREATE DATABASE organization_v3; CREATE DATABASE organization_v4;
  -- authorization
  CREATE DATABASE authorization_v0; CREATE DATABASE authorization_v1; CREATE DATABASE authorization_v2;
  CREATE DATABASE authorization_v3; CREATE DATABASE authorization_v4;
  -- notification
  CREATE DATABASE notification_v0; CREATE DATABASE notification_v1; CREATE DATABASE notification_v2;
  CREATE DATABASE notification_v3; CREATE DATABASE notification_v4; CREATE DATABASE notification_v5;
  -- file-storage
  CREATE DATABASE file_storage_v0; CREATE DATABASE file_storage_v1; CREATE DATABASE file_storage_v2;
  CREATE DATABASE file_storage_v3; CREATE DATABASE file_storage_v4;
  -- integration
  CREATE DATABASE integration_v0; CREATE DATABASE integration_v1; CREATE DATABASE integration_v2;
  CREATE DATABASE integration_v3; CREATE DATABASE integration_v4;
  -- usage-metering
  CREATE DATABASE usage_metering_v0; CREATE DATABASE usage_metering_v1; CREATE DATABASE usage_metering_v2;
  CREATE DATABASE usage_metering_v3; CREATE DATABASE usage_metering_v4;
  -- billing
  CREATE DATABASE billing_v0; CREATE DATABASE billing_v1; CREATE DATABASE billing_v2;
  CREATE DATABASE billing_v3; CREATE DATABASE billing_v4; CREATE DATABASE billing_v5;
  -- payment
  CREATE DATABASE payment_v0; CREATE DATABASE payment_v1; CREATE DATABASE payment_v2;
  CREATE DATABASE payment_v3; CREATE DATABASE payment_v4; CREATE DATABASE payment_v5;
EOSQL
```

10. Create docs/adr/0000-template.md — a standard ADR template (Title, Status, Context, Decision, Consequences, References sections).

11. Create docs/adr/0001-versions-coexist-and-vertical-first-build.md with:
    - Title: "Versions coexist as Gradle modules; vertical build per service"
    - Status: Accepted
    - Context: Multi-version learning platform; need to compare implementations side-by-side at runtime; parallel build across services via tmux + git worktrees
    - Decision: All versions live concurrently as Gradle modules under services/<svc>/v<N>-<name>/. Earlier versions are never modified; new versions are built by reading the previous version's source as reference but re-implementing in a fresh module. Each version has its own port and Postgres database.
    - Consequences: Larger repo (~50 Gradle modules at completion). Heavier disk + Gradle configuration time. Trade accepted because: any two versions can run on different ports for direct comparison; the diff between v(N-1) and v(N) is a teaching artifact; the "what changed" story for each version is explicit and reviewable.
    - References: MASTER-PLAN-V2.md, PARALLEL-WORKFLOW.md

12. Create .github/workflows/check.yml — a minimal CI workflow that runs on push to main and on PRs:
    - Uses ubuntu-latest
    - Sets up Java 21 (actions/setup-java with distribution: temurin, java-version: 21)
    - Sets up Gradle with caching
    - Runs ./gradlew check
    - For now will just succeed because no modules exist yet; placeholder for when services land

13. Create .gitignore covering:
    - Java/Gradle: .gradle/, build/, *.class
    - IntelliJ: .idea/, *.iml
    - VSCode: .vscode/
    - macOS: .DS_Store
    - Logs: *.log
    - Local env: .env, .env.local

14. Create .editorconfig with sensible defaults for Java (4-space indent), YAML/JSON/MD (2-space), trim trailing whitespace, insert final newline.

15. Create README.md at the repo root that:
    - Names the project: "backend-core"
    - One-paragraph description of the project's purpose
    - Repository layout summary (a compact version of what's in MASTER-PLAN-V2.md)
    - Quick start: link to SETUP-INITIAL.md and PARALLEL-WORKFLOW.md
    - Status section listing the current build phase
    - Links to MASTER-PLAN-V2.md, PARALLEL-WORKFLOW.md, docs/adr/

16. Create CONTRIBUTING.md describing:
    - Branch model: main + service/<svc> per service
    - Commit message format: "<service> v<N>-<name>: <description>"
    - The role of MASTER-PLAN-V2.md and per-version files in service-plans-v2/
    - The "do not edit earlier versions" rule
    - How to add a new ADR

17. Do NOT create any actual service code.
18. Do NOT add any Spring Boot dependencies in any module's build.gradle.kts (no modules exist yet anyway).
19. Do NOT run git commit. The user reviews and commits manually.

==========
DONE CRITERIA
==========

- Gradle wrapper present (./gradlew --version returns Gradle 8.x without error)
- All directories listed above exist with their .gitkeep files; `find . -name .gitkeep | wc -l` is at least 60
- ./gradlew help succeeds (configures cleanly with no modules)
- docker compose -f infra/compose/docker-compose.yml config validates (no actual `up` yet)
- ADR-0001 exists, internally consistent with MASTER-PLAN-V2.md and PARALLEL-WORKFLOW.md
- README.md, CONTRIBUTING.md, .gitignore, .editorconfig present
- .github/workflows/check.yml present and valid YAML
- service-plans-v2/identity/ is untouched (it was there before the prompt started; do NOT modify these files)

Stop when these are met.
```

---

## After this prompt completes

Verify by hand:

```bash
# Gradle works
./gradlew --version
./gradlew help

# All version directories present
find services -type d -name "v*" | sort
# Should list 49 directories (identity 7 + organization 5 + authorization 5 + notification 6 + file-storage 5 + integration 5 + usage-metering 5 + billing 6 + payment 6 = 50; one fewer if any miscounted)

find pkg -type d -name "v*" | sort
# Idempotency 4 + audit 5 = 9

find infra/observability -type d -name "v*" | sort
# 5 (v0 through v4)

# Settings file is the dynamic-discovery version
cat settings.gradle.kts

# Compose validates
docker compose -f infra/compose/docker-compose.yml config

# ADR present and reads correctly
cat docs/adr/0001-versions-coexist-and-vertical-first-build.md

# Bring up Postgres and check the per-version DBs exist
docker compose -f infra/compose/docker-compose.yml up -d postgres
docker compose -f infra/compose/docker-compose.yml exec postgres psql -U postgres -c '\l' | head -50
# Should list all the identity_v0 ... payment_v5 databases
docker compose -f infra/compose/docker-compose.yml down

# Git status
git status
# Many new files staged; nothing committed yet
```

If anything looks wrong, fix manually or ask Claude Code to adjust before committing.

When satisfied:

```bash
git add .
git commit -m "Initial setup: full repo skeleton + per-version DB scaffold + ADR-0001"
git push origin main
```

Now proceed to `PARALLEL-WORKFLOW.md` "One-time setup" section to create worktrees + tmux sessions, then start building identity v0.
