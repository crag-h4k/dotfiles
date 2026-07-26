# dotfiles

[![CI](https://github.com/crag-h4k/dotfiles/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/crag-h4k/dotfiles/actions/workflows/ci.yaml) [![Managed by chezmoi](https://img.shields.io/badge/managed%20by-chezmoi-2d3142)](https://chezmoi.io) [![Debian Trixie](https://img.shields.io/badge/Debian%20Trixie-A81D33?logo=debian&logoColor=white)](docs/ci.md) [![macOS](https://img.shields.io/badge/macOS-252525?logo=apple&logoColor=white)](docs/ci.md) [![Gum](https://img.shields.io/badge/picker-Gum-FF69B4)](https://github.com/charmbracelet/gum)

Professionally overengineered, personally unhinged dotfiles for people with
enterprise-level trust issues who think tmux deserves deployment CI. Chezmoi
wrangles Zsh, Neovim, Ghostty/iTerm2, Claude/Codex hooks, palettes, and tools.
Its home-grown notifier chirps or beeps and makes tmux change colors at you
when a long job, Claude, or Codex needs attention. Gum picks the loadout;
headless macOS/Trixie runners make sure nothing shits the bed.

## What this thing does

- Chirps or beeps and recolors the tmux pane and status flag when a long job,
  Claude, or Codex needs attention.
- Installs only the components and sub-features selected for a host.
- Keeps Ghostty, iTerm2, tmux, Neovim, Claude, and Codex on one shared palette.
- Handles the Ghostty → SSH → tmux mouse, clipboard, and scrollback gauntlet.
- Gives Neovim modern LSP activation, missing-only Mason installs, and
  non-blocking Gitleaks warnings.
- Plans and deduplicates packages before Homebrew or APT gets to touch anything.
- Proves clean, unattended installs on native macOS and Debian Trixie before
  `main` gets the privilege.
- Accumulates intentional releases instead of spraying tags after every merge.

## Quick start

Install `gum` for the checkbox picker, then let chezmoi bootstrap the rest:

```sh
# macOS
command -v gum >/dev/null || brew install gum
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k

# Debian Trixie
command -v gum >/dev/null || { sudo apt-get update && sudo apt-get install -y gum; }
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k
```

Without `gum`, the same choices appear as typed menus. Local terminals and
interactive SSH sessions both work.

The bootstrap:

1. Installs chezmoi and clones the source into
   `~/.local/share/chezmoi/`.
1. Opens the component, sub-feature, palette, and install-mode pickers.
1. Shows the deduplicated package plan before anything mutates a package
   manager.
1. Backs up managed files and nearby local state under
   `~/.dotfiles-backup/<timestamp>/`.
1. Applies the selected configuration and, in package mode, installs the
   approved tools.

Split init from apply if you want to inspect the plan first:

```sh
chezmoi init crag-h4k
chezmoi diff
chezmoi apply
```

For automation, choose the mode explicitly. Package mode also needs the
confirmation override; without it, a headless apply falls back to configs only.

```sh
DOTFILES_INSTALL_MODE=configs \
  chezmoi init --apply --no-tty crag-h4k

DOTFILES_INSTALL_MODE=packages DOTFILES_ASSUME_YES=1 \
  chezmoi init --apply --no-tty crag-h4k
```

## Who owns what

| Owner | Responsibility |
| --- | --- |
| Chezmoi | Component declarations, templates, configuration, externals, and host rendering |
| Package installer | General-purpose shell-visible tools from Homebrew, APT, GitHub releases, npm, pip, and LuaRocks |
| Mason | Neovim-only executables and the desired LSP server set |
| Lazy | Neovim plugins on the local machine |

Mason and Lazy install missing state, but they do not reconcile every host to
one exact runtime revision. `lazy-lock.json` stays ignored on purpose, so a
normal plugin update does not turn the dotfiles checkout dirty.

`markdownlint-cli2` is the deliberate exception to Mason ownership. It remains
shell-visible through Homebrew on macOS or user-global npm on Debian, and
Neovim's `nvim-lint` uses that same binary.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Components](docs/components.md) | Pickers, sub-features, package mode, and changing a host later |
| [Architecture](docs/architecture.md) | Source-root boundaries, ownership, and rendered paths |
| [Operation](docs/operation.md) | Daily chezmoi work, tmux behavior, statuslines, and removal |
| [Neovim](docs/neovim.md) | Lazy, Mason, LSPs, linters, and local revision state |
| [Gitleaks](docs/gitleaks.md) | Editor warnings, project allowlists, exclusions, and pre-commit enforcement |
| [Notifications](docs/notifications.md) | tmux-native process and Claude/Codex attention cues |
| [Palettes](docs/palettes.md) | Shared base16 catalog and authoring workflow |
| [CI](docs/ci.md) | PR metadata, pre-commit, and parallel macOS/Trixie deployments |
| [Releases](docs/releases.md) | Conventional titles, Release Please, SemVer, and deliberate publishing |
| [Contributing](CONTRIBUTING.md) | Branches, worktrees, tests, and squash-merge rules |
