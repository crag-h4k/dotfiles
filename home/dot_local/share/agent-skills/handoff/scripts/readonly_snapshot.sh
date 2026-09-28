#!/bin/sh
# $HOME/.local/share/agent-skills/handoff/scripts/snapshot.sh
# Print git state for the current directory. Do not print the environment or file contents.

set -eu

if ! command -v git >/dev/null 2>&1 || ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s\n' "git: no"
  printf '%s\n' "cwd: ${PWD}"
  exit 0
fi

printf '%s\n' "git: yes"
printf '%s\n' "toplevel: $(git rev-parse --show-toplevel)"
printf '%s\n' "branch: $(git branch --show-current)"
printf '%s\n' "head: $(git log -1 --format='%h %s')"
printf '%s\n' "status:"
git status --short
printf '%s\n' "worktrees:"
git worktree list
