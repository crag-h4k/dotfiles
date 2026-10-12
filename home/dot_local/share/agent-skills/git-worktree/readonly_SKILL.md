---
name: git-worktree
description: Inspect or create an isolated Git worktree using repository conventions and question-tool approvals. Use to start independent work or locate an existing branch checkout, not automatic cleanup.
---

# Isolate repository work

Adapted from EveryInc's `ce-worktree`; see `../PROVENANCE.md` and this
directory's MIT `LICENSE`. Preserve the user's existing worktree layout and
session ownership instead of defaulting every repository to `.worktrees/`.

## Inspect first

Read applicable instructions and resolve the checkout's actual root, branch,
dirty/staged state, remotes, and `git worktree list --porcelain`. The chezmoi
source may be a bare Git repository with files beside it; inspect its declared
Git/work-tree relationship explicitly rather than assuming ordinary `git status`
can run there. Do not change `core.bare` or other repository configuration.

Compare the resolved absolute Git dir and common Git dir, and check
`git rev-parse --show-superproject-working-tree` to distinguish a submodule from
a linked worktree. Existing isolation for the same task is enough: work there.
An independent feature must not reuse another task's checkout merely because
it is already a worktree. Naming another branch does not authorize switching
this session to it or moving another agent's work.

## Choose and authorize

Use the host's blocking question tool (`question` in OpenCode) for path/base
choices and every Git mutation, including fetch, branch creation, checkout and
worktree changes. In OpenCode, stop writes if `question` is unavailable or fails.
Only other harnesses lacking a blocking question tool may ask in chat and wait.
A tool error or dismissal means no action. Preview the exact destination, branch, base/ref,
remote, and operations; retain approval only for those named operations.

For new work, follow repository branch prefixes and start from current remote
main/default unless the user names a dependency. Refresh it only after fetch
approval. If refresh fails or no remote exists, report it and ask whether an
explicit local ref is acceptable; do not silently call a stale base current.
Use the configured worktree root. In this workstation's dotfiles workflow,
`/opt/worktrees/dotfiles-<slug>` is an established host layout, not a portable
requirement for every machine. Do not add public-repo machine configuration
just to record the host's path. Ask if no path convention is known.

If the named branch already has a worktree, report its path and ask whether to
reuse it. Never force a second checkout, remove it, or repurpose it. For a PR,
verify its head repository/owner and tracking remote before proposing a writable
checkout; a detached commit is a read-only review choice, not a publishing head.

## Create and verify

Prefer an available native worktree mechanism when it can honor the approved
path/base and make the tree visible to the current harness. Otherwise use
`git worktree add` with the approved explicit branch, path, and ref. Do not
install a plugin or create a new session as a workaround without permission.
Never transfer uncommitted files automatically; they remain in the old checkout.

After creation, verify the actual root, branch, base commit, cleanliness and
tracking configuration. When the new tree is the primary workspace, use the
host's session-directory tool if available; otherwise clearly report the path
and run subsequent tools there. Check the destination instructions before edits.
If creation fails, stop and offer retry/alternate path/stop through the question
tool; do not continue in the original tree as if isolation succeeded.

Report the verified worktree and any preserved dirty source state. Never prune,
remove a worktree, delete a branch, reset, restore, or clean as routine finishing.
Those require a separate request and scoped approval even after a PR is merged.
