# dotfiles

Single-repo dotfile deployment using [chezmoi](https://chezmoi.io). `~` is the
only repo you need to clone on a new host.

Consolidates my zsh, tmux, and Neovim configuration (formerly split across
`gud-zsh`, `gud-vim`, `gud-tmux`) into one chezmoi source tree. Upstream plugins
(oh-my-zsh, tpm, `tmux-*`, `zsh-*`) come from chezmoi externals, so nothing is
vendored and plugins refresh on their own.

## Table of Contents

- [Quick start (new host)](#quick-start-new-host)
- [How it works](#how-it-works)
- [What lives where](#what-lives-where)
- [Daily operation](#daily-operation)
- [Supported platforms](#supported-platforms)
- [Uninstall](#uninstall)

## Quick start (new host)

```sh
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k
```

This one line:

1. Installs `chezmoi` if missing.
1. Clones this repo into `~/.local/share/chezmoi/`.
1. Runs `chezmoi apply`, which:
   - Fetches every upstream plugin declared in `.chezmoiexternal.toml` and
     drops them under `~/.zsh/ohmyzsh`, `~/.zsh/custom/plugins/*`,
     `~/.tmux/plugins/*`.
   - Places `~/.zshrc`, `~/.zshenv`, `~/.tmux.conf` as real files and
     populates `~/.zsh/`, `~/.tmux/`, `~/.config/nvim/` with the tracked
     config.
   - Creates `~/.darglint` and `~/.config/yamllint` symlinks into the shared
     linter-configs.
   - Runs `run_before_00-backup.sh` first, which snapshots every currently
     managed file that already exists into `~/.dotfiles-backup/<timestamp>/`
     before anything is overwritten. Runs on every apply (installs and updates).
   - Runs `run_once_after_00-install.sh`, which calls `scripts/install.sh` to
     install chezmoi (to `~/.local/bin` if not already in PATH), brew/apt
     packages, pre-warm the Neovim plugin cache, and create a convenience
     symlink `~/tilde -> ~/.local/share/chezmoi`.

When it finishes, open a new terminal. `zsh` should be your login shell
already; if not, `sudo chsh -s "$(command -v zsh)" "$USER"`.

## How it works

- **Content I author** (configs, custom functions, install scripts, docs)
  lives in this repo as regular files following chezmoi naming conventions
  (`dot_zshrc` → `~/.zshrc`, `dot_zsh/aliases` → `~/.zsh/aliases`, etc.).
- **Upstream plugins** I don't author are declared in `.chezmoiexternal.toml`.
  chezmoi clones each at apply time and refreshes weekly. No git submodules,
  no vendoring.
- **System packages** (zsh, neovim, tmux, fzf, gh, zoxide, etc.) are installed
  by `scripts/install-*.sh` on first apply. One script per app plus a
  platform-aware orchestrator.

## What lives where

| Path in repo | Target on host | Notes |
|---|---|---|
| `dot_zshrc` | `~/.zshrc` | real file |
| `dot_zshenv` | `~/.zshenv` | real file |
| `dot_zsh/aliases` | `~/.zsh/aliases` | real file |
| `dot_zsh/bin/executable_*` | `~/.zsh/bin/*` | exec bit preserved |
| `dot_zsh/custom/functions/*.zsh` | `~/.zsh/custom/functions/*.zsh` | |
| `dot_zsh/custom/themes/gud.zsh-theme` | `~/.zsh/custom/themes/gud.zsh-theme` | custom oh-my-zsh theme; `ZSH_THEME="gud"` |
| `dot_tmux.conf` | `~/.tmux.conf` | real file |
| `dot_tmux/conf.d/*.conf` | `~/.tmux/conf.d/*.conf` | |
| `dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | lazy.nvim entrypoint |
| `dot_config/nvim/lazy-lock.json` | `~/.config/nvim/lazy-lock.json` | plugin version lock |
| `dot_config/nvim/lua/statusline.lua` | `~/.config/nvim/lua/statusline.lua` | |
| `dot_config/nvim/linter-configs/darglint` | `~/.config/nvim/linter-configs/darglint` | docstring style |
| `dot_config/nvim/linter-configs/flake8` | `~/.config/nvim/linter-configs/flake8` | python style; `flake8` alias appends it |
| `dot_config/nvim/linter-configs/tflint.hcl` | `~/.config/nvim/linter-configs/tflint.hcl` | terraform lint rules |
| `dot_config/nvim/linter-configs/markdownlint.yaml` | `~/.config/nvim/linter-configs/markdownlint.yaml` | used by nvim-lint for markdown files |
| `dot_config/nvim/linter-configs/yamllint/config` | `~/.config/nvim/linter-configs/yamllint/config` | |
| `symlink_dot_darglint` | `~/.darglint` (symlink) | → `.config/nvim/linter-configs/darglint` |
| `dot_config/symlink_yamllint` | `~/.config/yamllint` (symlink) | → `nvim/linter-configs/yamllint` (dir) |
| **System-level tool configs** | | |
| `dot_tfswitch.toml` | `~/.tfswitch.toml` | terraform version switcher |
| `dot_gitconfig` | `~/.gitconfig` | git main; includes the per-context configs below |
| `dot_gitconfig.personal` | `~/.gitconfig.personal` | personal identity (default) |
| `dot_gitconfig.work` | `~/.gitconfig.work` | work identity (loaded inside `~/work/**`) |
| `dot_gitignore_global` | `~/.gitignore_global` | global ignore patterns |
| `dot_profile` | `~/.profile` | minimal login shim (sources cargo env) |
| `.chezmoiexternal.toml` | (external clones) | 11 upstream plugins |

## Daily operation

```sh
# Edit a config file via chezmoi (so the source tree stays the source of truth):
chezmoi edit ~/.zshrc
chezmoi apply                      # materialize the edit into $HOME

# Or edit the source tree directly and then apply (~/tilde is a symlink to
# ~/.local/share/chezmoi, created by scripts/install.sh):
cd ~/tilde
$EDITOR dot_zshrc
chezmoi apply

# Pull upstream plugins now instead of waiting for weekly refresh:
chezmoi apply --refresh-externals

# Re-run the install scripts (e.g. after updating packages):
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply

# Inspect what chezmoi thinks should change:
chezmoi diff

# Sync chezmoi source with this repo's origin:
chezmoi update                     # git pull in source + apply
```

## Supported platforms

- macOS (Homebrew)
- Debian / Ubuntu (`apt-get`, with sudo)

Other Linux distros work if you install the listed binaries yourself; the
config is distro-agnostic.

## Uninstall

```sh
chezmoi purge          # removes chezmoi source and state
rm -rf ~/.zsh ~/.tmux ~/.config/nvim
rm ~/.zshrc ~/.zshenv ~/.tmux.conf ~/.darglint ~/.config/yamllint
```
