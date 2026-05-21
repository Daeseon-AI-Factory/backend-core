#!/bin/bash

# Usage:
#   ./tmux-core.sh <session-name> <project-path>
#
# Example:
#   ./tmux-core.sh backend-core ~/Documents/GitHub/backend-platform-core

SESSION="$1"
PROJECT_DIR="$2"

if [ -z "$SESSION" ] || [ -z "$PROJECT_DIR" ]; then
  echo "Usage: ./tmux-core.sh <session-name> <project-path>"
  echo "Example: ./tmux-core.sh backend-core ~/Documents/GitHub/backend-platform-core"
  exit 1
fi

# Expand ~ if used in path
PROJECT_DIR=$(eval echo "$PROJECT_DIR")

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project directory does not exist: $PROJECT_DIR"
  exit 1
fi

# If session already exists, attach to it
tmux has-session -t "$SESSION" 2>/dev/null
if [ $? -eq 0 ]; then
  echo "Session '$SESSION' already exists. Attaching..."
  tmux attach -t "$SESSION"
  exit 0
fi

# 1. Claude coding window
tmux new-session -d -s "$SESSION" -n "code" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:code" 'clear' C-m
tmux send-keys -t "$SESSION:code" 'echo "Window: code"' C-m
tmux send-keys -t "$SESSION:code" 'echo "Purpose: Claude coding / implementation"' C-m
tmux send-keys -t "$SESSION:code" 'echo ""' C-m
tmux send-keys -t "$SESSION:code" 'pwd' C-m

# 2. Claude review window
tmux new-window -t "$SESSION" -n "creview" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:creview" 'clear' C-m
tmux send-keys -t "$SESSION:creview" 'echo "Window: creview"' C-m
tmux send-keys -t "$SESSION:creview" 'echo "Purpose: Claude design review / diff review / cross-check"' C-m
tmux send-keys -t "$SESSION:creview" 'echo ""' C-m
tmux send-keys -t "$SESSION:creview" 'pwd' C-m

# 3. Codex review window
tmux new-window -t "$SESSION" -n "codex" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:codex" 'clear' C-m
tmux send-keys -t "$SESSION:codex" 'echo "Window: codex"' C-m
tmux send-keys -t "$SESSION:codex" 'echo "Purpose: Codex verification / bug check / test failure analysis"' C-m
tmux send-keys -t "$SESSION:codex" 'echo ""' C-m
tmux send-keys -t "$SESSION:codex" 'pwd' C-m

# 4. Server window
tmux new-window -t "$SESSION" -n "server" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:server" 'clear' C-m
tmux send-keys -t "$SESSION:server" 'echo "Window: server"' C-m
tmux send-keys -t "$SESSION:server" 'echo "Purpose: run app / docker compose / local services"' C-m
tmux send-keys -t "$SESSION:server" 'echo ""' C-m
tmux send-keys -t "$SESSION:server" 'pwd' C-m

# 5. Test window
tmux new-window -t "$SESSION" -n "test" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:test" 'clear' C-m
tmux send-keys -t "$SESSION:test" 'echo "Window: test"' C-m
tmux send-keys -t "$SESSION:test" 'echo "Purpose: tests / curl / API verification"' C-m
tmux send-keys -t "$SESSION:test" 'echo ""' C-m
tmux send-keys -t "$SESSION:test" 'pwd' C-m

# 6. Git window
tmux new-window -t "$SESSION" -n "git" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:git" 'clear' C-m
tmux send-keys -t "$SESSION:git" 'echo "Window: git"' C-m
tmux send-keys -t "$SESSION:git" 'echo "Purpose: git status / diff / commit"' C-m
tmux send-keys -t "$SESSION:git" 'echo ""' C-m
tmux send-keys -t "$SESSION:git" 'git status' C-m

# 7. Notes window
tmux new-window -t "$SESSION" -n "notes" -c "$PROJECT_DIR"
tmux send-keys -t "$SESSION:notes" 'clear' C-m
tmux send-keys -t "$SESSION:notes" 'echo "Window: notes"' C-m
tmux send-keys -t "$SESSION:notes" 'echo "Purpose: plan / Definition of Done / prompts / review findings"' C-m
tmux send-keys -t "$SESSION:notes" 'echo ""' C-m
tmux send-keys -t "$SESSION:notes" 'cat <<EOF > .tmux-notes-template.md
# Today

Goal:
-

Definition of Done:
- tests pass
- server runs
- curl verified
- git diff reviewed
- commit done

Current Task:
-

Claude-code Prompt:
-

Claude-review Prompt:
-

Codex-review Prompt:
-

Findings:
-

Next Commit:
-

Open Questions:
-
EOF' C-m
tmux send-keys -t "$SESSION:notes" 'cat .tmux-notes-template.md' C-m

# Start at notes window so you define the work first
tmux select-window -t "$SESSION:notes"

# Attach to session
tmux attach -t "$SESSION"
