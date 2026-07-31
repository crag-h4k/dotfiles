---
name: chezmoi-dotfiles
description: Maintain this repository's chezmoi components, cross-platform installers, templates, notifications, and validation. Use when changing dotfiles behavior, adding a component or AI sub-feature, or debugging an apply.
---

# Chezmoi dotfiles

Use the repository itself as the source of truth. Do not assume a checkout path,
username, host, Git remote, palette, or selected component.

## Start here

1. Find the repository root from the current working directory.
2. Read `AGENTS.md`, `docs/architecture.md`, `docs/components.md`, and the
   relevant installer or feature documentation.
3. Inspect `home/.chezmoi.toml.tmpl`, `home/.chezmoiignore`,
   `home/.chezmoiexternal.toml`, and the related tests before changing component
   behavior.

## Component changes

The component model is declared in `home/.chezmoi.toml.tmpl`. A component or
sub-feature may also require:

- a target gate in `home/.chezmoiignore`;
- an external gate in `home/.chezmoiexternal.toml`;
- a rendered apply script under `home/.chezmoiscripts`;
- installer behavior under `scripts/`;
- template-matrix coverage in `scripts/validate-templates.sh`;
- user documentation in `docs/components.md`.

Keep pure configuration work in chezmoi's file or apply-script layer. Do not
drive `chezmoi apply` recursively from an installer.

## Cross-platform rules

- Support the platforms documented by the repository.
- Keep OS-specific package and file behavior explicitly gated.
- Do not copy application preference databases or machine-generated state into
  the repository. Prefer declarative formats with stable fields.
- Avoid machine paths, account names, hostnames, private addresses, and
  credentials in tracked files.
- Preserve the repository's shell-version constraints.

## AI configuration

AI tooling is opt-in under the `ai` component. The shared authored workspace is
portable and configured through `data.aiDirectory`, defaulting to `~/ai`.
Claude and Codex may share authored instructions, skills, plans, specs, scripts,
and memory, but their authentication, transcripts, caches, databases, hook
formats, rule formats, and agent-role formats remain tool-specific.

## Validation

Run the narrow tests for the changed area first, then:

```bash
scripts/validate-templates.sh
pre-commit run --all-files
```

Do not commit or push unless the user explicitly requests it.
