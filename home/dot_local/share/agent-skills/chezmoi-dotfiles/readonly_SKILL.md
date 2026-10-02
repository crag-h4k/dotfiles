---
name: chezmoi-dotfiles
description: Maintain crag-h4k/dotfiles, its chezmoi component model, installation, terminal integrations, and agent guidance. Use for changes or diagnosis in this workstation repository, or an explicit refresh of its guidance.
---

# Dotfiles maintenance

Use the current repository and its scoped AGENTS.md files as the working
contract. This skill supports OpenCode2 and the shared compatible harnesses.
It does not grant permission to deploy, run privileged commands, or publish.

## Locate the work

If already in the requested checkout, use its Git root. Otherwise resolve the
configured chezmoi source and its enclosing Git root. `~/dotfiles` may be a
symlink and `.chezmoiroot` selects `home/`. Pass the repository root as
`--source`. If multiple active checkouts could be the target, ask before editing.

Identify the execution host, branch, dirty/staged files, and active worktrees.
An OpenCode2 client attached to a server can execute in another filesystem.
Use the actual tool environment and preserve another agent's work.

## Choose the work

- For a change or diagnosis, read the applicable child guidance and product
  documentation. Read `references/workflows.md` for component, package,
  deployment, or terminal work. In chezmoi source this reference is named
  `references/readonly_workflows.md`.
- For diagnosis or review, report findings. Edit only when the request authorizes
  a fix.
- For an explicit `refresh-guidance` request, read `references/decisions.md`
  (source: `references/readonly_decisions.md`). Review available user corrections,
  plans, commits, and current behavior. Update only affected rules/references.
  Do not scan full chat histories during routine implementation.
- For orientation with no task, report the actual checkout, relevant guidance,
  and validation entrypoints. Stop without changing files.

Keep explicit instructions and repeated decisions firm. Label supported
inferences as defaults and let current user choices override them. Current code
establishes behavior; historical plans can describe work that was superseded or
never implemented. Historical approval does not authorize another task.

## Complete the task

Use existing unmanaged overlays for private settings, preserve the canonical
palette and skill store, and keep package changes behind their approval flow.
Implement the requested behavior, run focused checks and the complete prek gate,
and update affected documentation/guidance. Report unavailable checks honestly.

Keep authored guidance public-safe: summarize decisions, cite public commits or
dates, and omit transcript identifiers, private paths, credentials, endpoints,
employer content, and raw logs. Preserve installed assets when the request is
repository-only. Commit, push, merge, publish, and deployment require the current
task's authorization.
