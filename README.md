# dotfiles

Single-repo dotfile deployment using [chezmoi](https://chezmoi.io). `~` is the
only repo you need to clone on a new host.

Consolidates my zsh, tmux, and Neovim configuration (formerly split across
`gud-zsh`, `gud-vim`, `gud-tmux`) into one chezmoi source tree. Upstream plugins
(oh-my-zsh, tpm, `tmux-*`, `zsh-*`) come from chezmoi externals, so nothing is
vendored and plugins refresh on their own.

chezmoi owns component selection, the shared color palette, and install mode.
The choices persist in `~/.config/chezmoi/chezmoi.toml`. `chezmoi apply` then
writes only the selected components and optionally installs the exact deduped
package plan shown during init. No wrapper script and no path juggling.

## Documentation

| Doc | What's inside |
| --- | --- |
| [Components](docs/components.md) | Choosing components, the git/ai/terminal sub-feature submenus, and changing your selection later |
| [Architecture](docs/architecture.md) | How chezmoi drives the repo, and a full table of what file lands where |
| [Notifications](docs/notifications.md) | The tmux-native notify subsystem and its standalone (no-chezmoi) installer |
| [Operation](docs/operation.md) | Daily chezmoi commands, tmux mouse/naming behavior, the statusline, platforms, and uninstall |

## Quick start (new host)

Install `gum` first so the component picker shows a checkbox TUI, then
bootstrap chezmoi:

```sh
# macOS
command -v gum >/dev/null || brew install gum
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k

# Debian Trixie
command -v gum >/dev/null || { sudo apt-get update && sudo apt-get install -y gum; }
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k
```

Without `gum` the pickers fall back to typed menus. Interactive local and SSH
sessions work normally because they have a controlling TTY.

The chezmoi bootstrap line:

1. Installs `chezmoi` if missing.
1. Clones this repo into `~/.local/share/chezmoi/`.
1. Prompts for components and a shared palette. Dracula is the default; the
   other choices are Catppuccin Mocha, Gruvbox Dark, and Tokyo Night.
1. Shows every deduped download grouped by source and marked `installed` or
   `planned`, then asks whether to install configs and packages, install configs
   only, or exit. Exit stops before any target file is applied.
1. Runs `chezmoi apply`, which:
   - Fetches the upstream plugins declared in `.chezmoiexternal.toml` for the
     selected components and drops them under `~/.zsh/ohmyzsh`,
     `~/.zsh/custom/plugins/*`, `~/.tmux/plugins/*`.
   - Places the selected components' files: `~/.zshrc`, `~/.zshenv`,
     `~/.tmux.conf` as real files and populates `~/.zsh/`, `~/.tmux/`,
     `~/.config/nvim/` with the tracked config.
   - Places the linter configs at their own conventional paths (`~/.darglint`,
     `~/.flake8`, `~/.tflint.hcl`, `~/.markdownlint.yaml`, `~/.config/yamllint`).
   - Runs `run_before_00-backup.sh` first, which snapshots the previous
     (pre-apply) version of your configs into `~/.dotfiles-backup/<timestamp>/`
     before anything is overwritten - every managed file plus colocated
     non-managed state / local additions (e.g. `lazy-lock.json`, a hand-added
     `~/.tmux/conf.d/*.conf`). Re-fetchable git externals (oh-my-zsh, tmux/zsh
     plugins) and app-state dirs with secrets/logs (`~/.claude`, `~/.codex`) are
     skipped. Runs on every apply; keeps the most recent `DOTFILES_BACKUP_KEEP`
     (default 20) snapshots.
   - Runs `run_once_after_00-install.sh`, which exports the component selection
     and saved install mode. Package mode installs the displayed Homebrew, apt,
     cask, GitHub release, npm, pip, and LuaRocks work. Configs-only mode skips
     those side effects but still applies configs, selected git externals, safe
     symlinks, iTerm2 defaults, and feature sentinels.

When it finishes, open a new terminal. `zsh` should be your login shell
already; if not, `sudo chsh -s "$(command -v zsh)" "$USER"`.

To answer the prompts before applying, split the steps:

```sh
# macOS
command -v gum >/dev/null || brew install gum

# Debian Trixie
command -v gum >/dev/null || { sudo apt-get update && sudo apt-get install -y gum; }

chezmoi init crag-h4k      # clone + prompt for components
chezmoi apply              # write only the selected components
```

Non-interactive init must choose a mode explicitly so automation cannot apply
or install by accident. Installing packages unattended also needs
`DOTFILES_ASSUME_YES=1`; it answers the confirmation that `install.sh` shows
before touching a package manager, so without it a no-terminal apply declines
and writes configs only.

```sh
DOTFILES_INSTALL_MODE=configs chezmoi init --apply crag-h4k
DOTFILES_INSTALL_MODE=packages DOTFILES_ASSUME_YES=1 chezmoi init --apply crag-h4k
```
