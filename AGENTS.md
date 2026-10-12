# Dotfiles agent contract

This is `crag-h4k/dotfiles`: a selective, chezmoi-managed developer workstation
for macOS and Debian Trixie. The integrated tmux notifier, coherent terminal
palette, AI tooling, and verified deployments are central to the project.

## Start here

- Identify the execution host, real Git root, branch, worktrees, and dirty files
  before changing anything. `~/dotfiles` can be a symlink. An attached OpenCode2
  session can execute somewhere different from the terminal running its client.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) and the documentation for the behavior
  you are changing. Read every applicable child `AGENTS.md` before editing;
  descendant files may need explicit loading when a session starts at the root.
- For maintenance, read the repository's
  [chezmoi-dotfiles skill](home/dot_local/share/agent-skills/chezmoi-dotfiles/readonly_SKILL.md).
  It is usable from source before the shared skill is installed. Installed
  copies and old plans can lag behind the current checkout.

| Work | Additional guidance |
| --- | --- |
| Managed configuration | [home/AGENTS.md](home/AGENTS.md) |
| Packaging and authoring scripts | [scripts/AGENTS.md](scripts/AGENTS.md) |
| Tests and deployment fixtures | [tests/AGENTS.md](tests/AGENTS.md) |
| CI and releases | [.github/AGENTS.md](.github/AGENTS.md) |
| Documentation | [docs/AGENTS.md](docs/AGENTS.md) |
| OpenCode2 | [OpenCode guidance](docs/opencode-maintenance.md) |
| Neovim | [Neovim guidance](home/dot_config/nvim/AGENTS.md) |
| Notifications | [Notifier guidance](home/dot_config/notify/AGENTS.md) |

## Working agreements

- Carry an authorized change through implementation, appropriate checks, and
  documentation. Investigate facts in the repo before asking. Ask about choices
  that change the result; do not repeatedly request permission for ordinary edits.
- Preserve existing edits, the staging tree, active sessions, and another
  agent's checkout. Use separate worktrees for independent feature work. Start
  new features from current `main` unless the user names an existing branch or
  dependency. Keep large feature series reviewable in dependency order.
- Never commit, push, merge, publish, or change repository settings without
  explicit authorization for the current task. Past chat approval is not a grant
  for a new operation. Follow the branch and PR conventions in CONTRIBUTING.
- Do not execute commands requiring root or sudo. Respect any explicit host
  policy for read-only remote access. If privileged work is necessary, provide
  the exact command and a commented executable handoff script using the active
  host's `handoff-scripts` convention. Do not run it yourself.
- The repo is public. Keep credentials, identities, private endpoints, employer
  material, private permissions, session records, and host-specific routing
  outside it. Plan's narrow portable handoff-root rules are managed source.
  Use existing unmanaged overrides. Inspect approved private state when needed
  without printing secrets or importing that state into public files.

## Project defaults

- Keep managed declarations under `home/`; `.chezmoiroot` selects that directory.
  Pass the repository root to `chezmoi --source`, including for worktrees.
- Keep package approval meaningful: preview the deduplicated operations, apply
  those candidates, skip current packages, and show failures and long phases.
- Honor `data.palette` and the existing terminal design. Gud is the default Zsh
  prompt and Dracula is the default palette. A user's selected scheme takes
  precedence. Share semantic colors across consumers.
- Preserve per-entry skill overlays and private configuration escape hatches.
  Runtime caches, authentication, plugin runtimes, and local revision state stay
  outside managed source.
- Match nearby code and current upstream APIs. Check an installed version or a
  primary source before prescribing flags. Avoid adding wrappers, abstractions,
  dependencies, or fallback behavior without a concrete need.

## Finish the change

Run focused checks while iterating, then `python3 scripts/prek-changed.py`
before review. CI runs `prek run --all-files`; the complete macOS/Trixie
deployment gate remains required for merging. Record
what ran, any failures or unavailable checks, and what still needs human review.
Never weaken the gate to obtain a green result.

Update affected project docs and guidance when behavior or a durable decision
changes. Keep procedures in the skill references and rules near their code.
Historical evidence belongs in the decisions reference; raw transcripts do not.
Explicit current instructions override these defaults. Report the actual checkout,
changed files, validation, and deployment state in plain language.
