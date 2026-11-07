<!-- docs/principles.md -->
# Principles

What this repository is for, what it refuses to manage, and how a change gets
judged. Read it before proposing a change. The
[decisions record](../home/dot_local/share/agent-skills/chezmoi-dotfiles/references/readonly_decisions.md)
keeps the dated reasoning; this page keeps the current answers.

Opinions are defaults that a host's own selection overrides. Principles are
rules, except the one marked as a default.

## Table of Contents

- [Purpose](#purpose)
- [Scope](#scope)
  - [Adopting a new tool](#adopting-a-new-tool)
- [Opinions](#opinions)
- [Guiding principles](#guiding-principles)
- [Judging a change](#judging-a-change)
- [Changing the principles](#changing-the-principles)

## Purpose

This is one maintainer's workstation for macOS and Debian Trixie, managed with
chezmoi. The maintainer is the first user, and that daily setup decides what
gets built.

Anyone else can take it as it is. The picker chooses what lands on a host, and
the main tools each read an unmanaged override file, so an adopter changes
behavior without editing the repository.

## Scope

| In scope | What is managed |
| --- | --- |
| Shell | Zsh, Oh My Zsh plugins, the Gud prompt, aliases, and functions |
| Multiplexer | tmux, its plugin set, and the status bar |
| Editor | Neovim, with Lazy, Mason, language servers, and linters |
| Terminal emulators | Ghostty, and iTerm2 Dynamic Profiles on macOS |
| Git | Generic behavior and the global ignore file |
| CLI tools | General-purpose tools in the package plan and their configs |
| Palette | One color catalog rendered into every consumer |
| AI harnesses | Generic OpenCode, Claude Code, Codex, and Copilot configuration and shared skills, as an opt-in component |
| Glue | The tmux notifier, wrappers such as `opencode2`, hooks, and statuslines that connect the tools above |

| Out of scope | Where it lives instead |
| --- | --- |
| Employer or work configuration of any kind | Private overlays on the host that needs it |
| Secrets and identities | `~/.zsh_private`, `~/.gitconfig.override`, or the OS keychain |
| Machine-specific paths and routing | Override files, or chezmoi data such as `worktreesDir` |
| Application state: project lists, window positions, auth and pairing tokens | The application. This is why iTerm2 gets Dynamic Profiles instead of its preferences plist |
| Self-updating internals: OpenCode's runtime `node_modules`, `lazy-lock.json`, TPM's plugin tree, Mason packages | The tool that updates them |
| Tools the maintainer has not adopted yet | A hand install, until it sticks |

### Adopting a new tool

A new tool is tried by hand first. Once it sticks, it can get a thin opt-in
component that installs it and wires it to pieces the repository already
manages. Nothing more: its own settings file, sync or remote features, and
updates stay with the tool.

A desktop GUI front end for OpenCode, for example, would get an install step
and one seeded setting pointing it at the managed `opencode2` wrapper. Its
settings file, remote access, and self-updates would stay unmanaged. The
OpenViking component already works this way: dotfiles installs the runtime and
service definitions, and the live configuration and memory stay private.

## Opinions

| Opinion | Default | Change it with |
| --- | --- | --- |
| Components | Zsh, tmux, Neovim, and Git | The component picker (`ccomp`) |
| AI tooling | Off | The AI component and its submenu |
| Terminal emulators | Off; Ghostty is the submenu default | The terminal component and its submenu |
| Prompt | Gud | `data.zshTheme` |
| Palette | Dracula | The `theme` setup action or `data.palette` |

The palette is one committed catalog, `home/.chezmoidata/palettes.yaml`,
generated from base16 sources at authoring time. Apply renders it into every
terminal, editor, and AI surface without the generator, the submodule, or the
network.

## Guiding principles

### Opt in through chezmoi

Outside a small base set (bootstrap tools, Gum, Lazygit, prek, and the
standalone linter configs), nothing installs unless its component is selected.
Nothing AI-related installs unless the AI component is.

Gates live in chezmoi's own templated `home/.chezmoiignore` and
`home/.chezmoiexternal.toml`, so an unselected component has neither files nor
externals. The installer runs after apply and reads the saved selection; no
script drives `chezmoi apply`. Sub-features join an existing parent where they
can: shared skills and MCP runtimes add no picker rows.

### Public-safe by construction

The repository is public. Private and work settings live in unmanaged overlays
that load after the managed config: the per-tool override files,
`~/.zsh_private`, and the `~/.gitconfig.override` include. The unconditional
block in `home/.chezmoiignore` lists every overlay, so chezmoi never writes
them and `chezmoi add` refuses them. That block is the anti-leak guard and
stays unconditional.

### Change behavior without editing the repo

An adopter should never need a fork to change a setting. Ghostty, tmux, Zsh,
Neovim, Git, and OpenCode each have one optional override that loads after the
managed base (see [Local overrides](operation.md#local-overrides)), and saved
chezmoi data such as `palette` and `worktreesDir` wins over defaults on
re-init. That keeps `chezmoi update` working on an adopted host. A tool that
gains managed config should get the same kind of hatch.

### Merge files that applications also write

OpenCode, Claude Code, and Codex write their own config files, so dotfiles
merges into them with `modify_` programs. A merge owns a marked section or a
short list of enforced keys, adds other defaults only where a key is absent,
and keeps user edits, unknown keys, and comments where the format has them.
Ambiguous or malformed input gets a warning and an untouched file.

### Preview, approve, and batch package work

One package run refreshes metadata, shows one deduplicated plan, asks once with
a default of no, and installs exactly the approved candidates in batched
Homebrew or APT calls. Current packages are skipped.

Configs-only is a supported mode in its own right, and declining or a headless
run without `DOTFILES_ASSUME_YES=1` falls back to it. Exact pins stay pinned
until the source changes. Floating tools move only when asked: through package
mode, or the tool's own update command such as OpenCode's `/update`.

### Two platforms, proven by CI

macOS (Homebrew) and Debian Trixie are both first-class; OS-only features such
as iTerm2 are gated on the OS too. Every pull request runs unattended
package-mode installs on both, then smoke tests that launch what was installed.

Complete coverage beats a selective speedup: speed CI up with caching and
parallel jobs, not by skipping checks. Green CI is evidence. A change is done
when it behaves correctly in the real terminal chain, and nobody weakens a gate
to get a green result.

### Small changes over new frameworks

This one is a default. Prefer an existing integration point, helper, or
component over a new wrapper, abstraction, dependency, or fallback, and push
back on scope growth. The repository removes features rather than carry them:
OpenCode V1 support went in 1.0.0, the `all+` selection was retired, and a
tab-sorting experiment was deleted without a replacement.

### Fail soft and say so

Independent steps keep going after one fails, and the final result still
reports the failure so chezmoi can retry. Installer runs keep their output,
plan, and exit status in a private log that `scripts/install.sh --log` shows.
Outside approved package work, apply does not escalate: when it cannot create a
directory, it prints the privileged command for the user.

### Docs move with code

A behavior change and its docs land in the same pull request. Docs describe
behavior, the commands that control it, and known limitations; they do not
track execution status or keep a work log. Markdown passes markdownlint. prek
runs the hooks in `.pre-commit-config.yaml`, and mdformat is not used.

### Reviewable branches, deliberate releases

Each change gets a feature branch in a flat
`$DOTFILES_WORKTREES_DIR/<repo>-<slug>` worktree, a Conventional Commit title
that matches its branch prefix, and a squash merge to `main`. A release exists
only when someone deliberately merges the pending Release Please PR. See
[Contributing](../CONTRIBUTING.md) and [Releases](releases.md).

### Agents ask every time

Repository work never authorizes a live `chezmoi apply`, a package install, or
a Git mutation. Each needs the maintainer's explicit approval for that
operation and scope, and approval from an earlier task does not carry over.
Agents never run `sudo`; they hand over the exact command.

The one written exception: syncing a feature branch with its base by a fetch
and a plain merge titled `chore: merge <base> into <branch>`. Pushing the
result still asks.

### Pin and verify what you fetch

Third-party skill files steer agents, so they are pinned to exact commit URLs
and per-file SHA-256 checksums. Release downloads are checksum-verified, and
prek hooks and the palette submodule are pinned by revision. Floating packages,
such as npm CLIs, plugin checkouts, and the maintainer's own OpenCode plugins
on `@latest`, move only through an explicit update. Gitleaks runs as a prek
hook, and authored agent guidance passes the public-text scan in
`scripts/validate-agent-skills.py`.

## Judging a change

Run these before proposing a change. Any "no" needs a reason in the pull
request, or a change to this page first.

1. Scope: does it fit [Scope](#scope), and is any new tool already in daily use
   by hand?
1. Opt-in: is it behind an existing component or sub-feature, gated in
   `.chezmoiignore` and `.chezmoiexternal.toml`?
1. Public-safe: do private, work, and machine-specific values stay in overlays?
1. Ownership: if the application writes the file too, is it merged rather than
   owned?
1. Overrides: can an adopter change it without editing the repository?
1. Platforms: does it work, or gate cleanly, on macOS and Trixie, in typed and
   headless setup?
1. Packages: does every package change go through the plan and its approval?
1. Size: is it the smallest change that works, built on existing helpers?
1. Docs: are the topic page and nearest agent guidance updated in the same
   change?
1. Approval: has the maintainer approved every live apply, install, or Git
   write it needs?

## Changing the principles

Change this page in its own pull request, so a principle never moves as a side
effect of a feature. When a change reverses an earlier decision, add a dated
entry to the decisions record explaining why.

A current explicit instruction from the maintainer wins over anything here. An
agent that finds a conflict between a request and this page names it before
acting, follows the instruction, and proposes an update to this page.
