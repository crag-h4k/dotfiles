---
name: git-worktree
description: Inspect or create an isolated Git worktree using repository conventions and question-tool approvals. Use to start independent work or locate an existing branch checkout, not automatic cleanup.
---

# Isolate repository work

Adapted from EveryInc's `ce-worktree`; see `../PROVENANCE.md` and this
directory's MIT `LICENSE`. Preserve the user's existing worktree layout and
session ownership instead of defaulting every repository to `.worktrees/`.

## Inspect first

Read applicable instructions and resolve the candidate directory physically
(`pwd -P`); `~/dotfiles` may be a symlink. Before `--show-toplevel`, `git status`,
or working-tree/index diffs, run these bare-safe probes with `candidate` set to
that directory:

```sh
git -C "$candidate" rev-parse --is-bare-repository
git -C "$candidate" rev-parse --is-inside-work-tree
git -C "$candidate" rev-parse --absolute-git-dir
git -C "$candidate" worktree list --porcelain
```

If inside a worktree, resolve its root, branch, dirty/staged state, and remotes.
Otherwise use the listing to locate the requested task's checkout, or propose
creating one. A `bare` entry is not a checkout, even if chezmoi source files sit
beside `.git`. Do not interpret a failed status as a clean source or change
`core.bare`/`core.worktree` to make a checkout-only command succeed.

If files beside a bare `.git` are confirmed to be the chezmoi source, inspect
their existing edits read-only with an explicit pairing, for example
`git --git-dir="$git_dir" --work-tree="$source_root" status --short`. Set both
paths from verified discovery; do not guess a work tree for an ordinary bare
store. This inspection does not authorize staging, checkout, or publishing there.
Preserve those files and the index; never copy them into a new tree automatically.

Once inside the selected checkout, compare its absolute Git dir and common Git
dir, and check `git rev-parse --show-superproject-working-tree` to distinguish a
submodule from a linked worktree. Existing isolation for the same task is enough:
work there.
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
path/base, handle the discovered Git context, and make the tree visible to the
current harness. A helper that requires `--show-toplevel` or `status` at the bare
source cannot do that. Use Git directly instead, with `git_dir` set to the
discovered absolute Git directory and the approved branch, destination, and ref:

```sh
git --git-dir="$git_dir" worktree add -b "$branch" "$destination" "$base"
```

`worktree add` works from a bare repository; it does not need `--work-tree`.
Do not prepend checkout-only checks at the source or run post-create checks
there. `fatal: this operation must be run in a work tree` from such a check
means the command used the wrong context, not that Git configuration needs repair.
Do not install a plugin or create a new session as a workaround without permission.
Never transfer uncommitted files automatically; they remain in the old checkout.

After creation, use `git -C "$destination" ...` to verify
`rev-parse --is-inside-work-tree` is `true`, then the actual root, branch, base
commit, cleanliness and tracking configuration. When the new tree is the primary
workspace, use the host's session-directory tool if available; otherwise clearly
report the path and run subsequent tools there. Check the destination instructions
before edits.
If creation fails, stop and offer retry/alternate path/stop through the question
tool; do not continue in the original tree as if isolation succeeded.

Report the verified worktree and any preserved dirty source state. Never prune,
remove a worktree, delete a branch, reset, restore, or clean as routine finishing.
Those require a separate request and scoped approval even after a PR is merged.
