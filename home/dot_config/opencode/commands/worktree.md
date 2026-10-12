---
description: Find or create a worktree with explicit Git approvals
---

# Worktree isolation

Treat `$ARGUMENTS` as task input, not authorization for Git mutations.
Load the `git-worktree` skill and follow it. No arguments reports the current
worktree state and asks which task/ref to isolate; it makes no changes.
