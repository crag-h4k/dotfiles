---
description: Find or create a worktree with explicit Git approvals
---

# Worktree isolation

Treat `$ARGUMENTS` as task input, not authorization for Git mutations.
Load the `git-worktree` skill and follow it. No arguments reports the current
worktree state and asks which task/ref to isolate; it makes no changes. A new
worktree goes under `$DOTFILES_WORKTREES_DIR` (default `$HOME/worktrees`) as
`<repo>-<slug>`, after the skill's approval preview.
