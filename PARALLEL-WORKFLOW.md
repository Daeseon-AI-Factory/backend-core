# Parallel Workflow

How to build multiple services concurrently in this monorepo without merge conflicts.

---

## Mental model

- **One repo**, at the user's chosen path (e.g., `~/code/backend-core`)
- **One `main` branch** holds shared infrastructure: `pkg/`, `infra/compose/docker-compose.yml` base, `settings.gradle.kts`, README, ADRs, master plan
- **One branch per service**: `service/identity`, `service/organization`, etc. Each branch only modifies its own service folder + its own compose overlay
- **One git worktree per service branch**: a physically separate directory on disk, sharing the single `.git`
- **One tmux session per active worktree**: each runs its own Claude Code instance reading that service's plan files

A new version is built by opening the relevant worktree's tmux session, copying the version's "Claude Code prompt" block from `service-plans-v2/<svc>/v<N>-*.md`, and pasting it into Claude Code.

---

## Coordination contract — who touches what

| File / directory | Touched by |
|---|---|
| `services/<svc>/v*/` | Only the `service/<svc>` branch |
| `infra/compose/overlays/<svc>-v*.yml` | Only the `service/<svc>` branch |
| `pkg/*/v*/` | Only `main` (a dedicated session for pkg work) |
| `infra/compose/docker-compose.yml` (base) | Only `main` |
| `infra/observability/v*/` | Only `main` |
| `settings.gradle.kts` (root) | Only `main`; service branches add their module by creating a folder — root discovery picks it up |
| `README.md`, `docs/adr/`, `MASTER-PLAN-V2.md` | Only `main` |
| `ui/frontend/` | Its own branch `service/ui` and its own worktree |
| `docs/comparisons/` | `main` |

**Rule of thumb:** if your tmux session is in `worktrees/identity/`, the only file outside `services/identity/` you may modify is `infra/compose/overlays/identity-v*.yml`. Anything else requires switching to `main`.

---

## The settings.gradle.kts dynamic discovery trick

Initial Setup writes `settings.gradle.kts` to walk the filesystem at configuration time and include every module it finds:

```kotlin
rootProject.name = "backend-core"

// Discover service-version modules dynamically
file("services").listFiles()?.filter { it.isDirectory }?.forEach { svc ->
    svc.listFiles()?.filter { it.isDirectory && it.name.startsWith("v") }?.forEach { version ->
        val moduleName = ":services:${svc.name}:${version.name}"
        include(moduleName)
        project(moduleName).projectDir = version
    }
}

// Same for pkg modules
file("pkg").listFiles()?.filter { it.isDirectory }?.forEach { mod ->
    val versionDirs = mod.listFiles()?.filter { it.isDirectory && it.name.startsWith("v") }
    if (versionDirs != null && versionDirs.isNotEmpty()) {
        versionDirs.forEach { v ->
            include(":pkg:${mod.name}:${v.name}")
            project(":pkg:${mod.name}:${v.name}").projectDir = v
        }
    } else {
        include(":pkg:${mod.name}")
    }
}
```

A service branch creates `services/identity/v3-oauth/` and the root build picks it up automatically — no edit to root, no merge conflict.

---

## One-time setup (run once, on main, after Initial Setup is committed and pushed)

```bash
cd ~/code/backend-core
git checkout main
git status   # must be clean

# Create branches for each service (all forked from main)
for svc in identity organization authorization notification file-storage integration usage-metering billing payment ui; do
  git branch service/$svc main
done

# Create worktrees alongside the main repo
mkdir -p ../worktrees
for svc in identity organization authorization notification file-storage integration usage-metering billing payment ui; do
  git worktree add ../worktrees/$svc service/$svc
done

# Verify
git worktree list
```

Result: ten worktrees, each on its own branch, sharing one `.git` directory.

```
~/code/backend-core/             ← main
~/code/worktrees/identity/        ← service/identity
~/code/worktrees/organization/    ← service/organization
... (8 more)
```

---

## tmux sessions

Create one session per service, detached:

```bash
SERVICES=(identity organization authorization notification file-storage integration usage-metering billing payment ui)

for svc in "${SERVICES[@]}"; do
  tmux new-session -d -s "$svc" -c ~/code/worktrees/$svc
done

# List
tmux ls

# Attach to one
tmux attach -t identity

# Detach with Ctrl-b d
```

Inside each session, launch Claude Code:

```bash
claude --permission-mode acceptEdits
```

Send the first prompt by copying the relevant version's "Claude Code prompt" block from `service-plans-v2/<svc>/v<N>-*.md`.

---

## Resource warning

- Each Claude Code session consumes RAM and CPU
- Running 10 concurrent Claude Code instances will saturate most laptops
- Realistic concurrency: 3–4 active sessions at a time
- The sessions can be *created* upfront and *attached/detached* as needed; only an attached session with active work is heavy

**Recommended order for early rounds:**
1. **identity** first, alone — every other service depends on it for user resolution
2. Once identity v0 is built, add **organization** (calls identity HTTP) and **notification** (no dependencies until later versions)
3. Add the rest gradually

---

## Rebase rhythm

When `main` gains anything (a new ADR, a new pkg version, a base compose file change), each service branch should rebase to stay current:

```bash
cd ~/code/worktrees/identity
git fetch origin
git rebase origin/main
```

Suggested timing:
- After Initial Setup lands → all worktrees fresh, no rebase needed
- After any `pkg/` version is built on main → service branches that need it rebase
- After major compose base changes → all branches rebase

---

## When a service version is "done"

Done criteria per `service-plans-v2/<svc>/v<N>-*.md`. When met:

```bash
cd ~/code/worktrees/<svc>
git add services/<svc>/v<N>-* infra/compose/overlays/<svc>-v<N>.yml
git commit -m "<svc> v<N>-<name>: <one-line description>"
git push origin service/<svc>
```

Optionally open a PR to main. Or merge directly when ready:

```bash
cd ~/code/backend-core
git checkout main
git merge --no-ff service/<svc>
git push origin main
```

---

## Working with shared modules (pkg, infra/observability)

These are built on `main`, not in a service worktree:

```bash
cd ~/code/backend-core
git checkout main

claude --permission-mode acceptEdits
# Paste the relevant prompt from service-plans-v2/<module>/...

# When done:
git add pkg/...
git commit -m "pkg/idempotency v0: DB-backed idempotency filter"
git push origin main
```

After a pkg version lands on main, service branches that depend on it should rebase before continuing.

**Order matters for cross-cuts:**
- `pkg/idempotency v0` before `notification v3` (uses outbox + idempotency keys)
- `pkg/audit v0` before any service v4+ (authorization v4, file-storage v4, payment v4, identity v6 all emit audit)
- `infra/observability v2` before any service v5 (identity v5 etc. need an OTLP endpoint to send traces to)

---

## Common pitfalls

| Problem | Cause | Fix |
|---|---|---|
| `fatal: '<branch>' is already used by worktree at ...` | Same branch checked out in another worktree | One branch per worktree; remove the old one with `git worktree remove` |
| Merge conflict on `settings.gradle.kts` | Multiple branches edited the root settings file | Don't edit root settings; the dynamic discovery picks up new modules automatically |
| Claude Code looks at the wrong version | Session started in the wrong directory | Always check `pwd` inside the tmux session before pasting a prompt |
| Service can't reach identity | Wrong container name or network | Each service's compose overlay declares the network and depends_on; check `docker network ls` |
| Two Claude Code instances double-process | Same worktree open in two sessions | One Claude Code per worktree |

---

## When something goes wrong

1. Don't panic-commit. Inspect with `git status` and `git diff`
2. Worst case: `git reset --hard` in the worktree returns to the branch's last commit (only loses uncommitted work in that worktree; other worktrees untouched)
3. Wipe a worktree entirely: `git worktree remove ../worktrees/<svc>` then recreate
4. The `.git` directory at the main repo is the single source of truth; worktrees are cheap and disposable
