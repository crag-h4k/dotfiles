# dotfiles

Single-repo dotfile deployment using [chezmoi](https://chezmoi.io). `~` is the
only repo you need to clone on a new host.

Consolidates my zsh, tmux, and Neovim configuration (formerly split across
`gud-zsh`, `gud-vim`, `gud-tmux`) into one chezmoi source tree. Upstream plugins
(oh-my-zsh, tpm, `tmux-*`, `zsh-*`) come from chezmoi externals, so nothing is
vendored and plugins refresh on their own.

chezmoi owns component selection. You pick zsh, tmux, neovim, and gitconfig once
at `chezmoi init`. The choice persists in `~/.config/chezmoi/chezmoi.toml`.
`chezmoi apply` then writes only the selected components' files and keeps them
current. No wrapper script and no path juggling.

## Table of Contents

- [Quick start (new host)](#quick-start-new-host)
- [Choosing components](#choosing-components)
- [Changing components later](#changing-components-later)
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
1. Prompts for which components to install (numbered menu, see below) and saves
   the answer to `~/.config/chezmoi/chezmoi.toml`.
1. Runs `chezmoi apply`, which:
   - Fetches the upstream plugins declared in `.chezmoiexternal.toml` for the
     selected components and drops them under `~/.zsh/ohmyzsh`,
     `~/.zsh/custom/plugins/*`, `~/.tmux/plugins/*`.
   - Places the selected components' files: `~/.zshrc`, `~/.zshenv`,
     `~/.tmux.conf` as real files and populates `~/.zsh/`, `~/.tmux/`,
     `~/.config/nvim/` with the tracked config.
   - Places the linter configs at their own conventional paths (`~/.darglint`,
     `~/.flake8`, `~/.tflint.hcl`, `~/.markdownlint.yaml`, `~/.config/yamllint`).
   - Runs `run_before_00-backup.sh` first, which snapshots every currently
     managed file that already exists into `~/.dotfiles-backup/<timestamp>/`
     before anything is overwritten. Runs on every apply (installs and updates).
   - Runs `run_once_after_00-install.sh`, which exports the component selection
     as `INSTALL_*` env vars and calls `scripts/install.sh` to install brew/apt
     packages for the selected components, pre-warm the Neovim plugin cache, and
     create a convenience symlink `~/dotfiles -> ~/.local/share/chezmoi`.

When it finishes, open a new terminal. `zsh` should be your login shell
already; if not, `sudo chsh -s "$(command -v zsh)" "$USER"`.

To answer the prompts before applying, split the steps:

```sh
chezmoi init crag-h4k      # clone + prompt for components
chezmoi apply              # write only the selected components
```

## Choosing components

`chezmoi init` shows a numbered menu:

```text
Components to install:
  1) zsh           oh-my-zsh, plugins, custom functions, aliases
  2) tmux          tmux + plugins (tpm, resurrect, sensible, yank)
  3) neovim        neovim, lazy.nvim, language servers, linters
  4) gitconfig     copy ~/.gitconfig* from repo examples
  5) codecompanion CodeCompanion.nvim AI assistant, opt-in (needs neovim)

Enter numbers (e.g. "1 3"), all, all+, or press Enter for default (1 2 3):
```

- Numbers: any subset (e.g. `1 3` for zsh + neovim). Spacing and order do not
  matter - `1 3`, `13`, and `3 1` are equivalent.
- Enter: the default, `1 2 3` (zsh + tmux + neovim, no gitconfig, no codecompanion).
- `all`: zsh + tmux + neovim.
- `all+`: everything including gitconfig and codecompanion.

`codecompanion` is opt-in (off in the default set and in `all`) because the
assistant ships buffer contents to an LLM. Selecting it provisions a sentinel
file (`~/.config/nvim/.codecompanion-enabled`) that `init.lua` checks at startup;
you can `touch`/`rm` that file to flip it per-host without re-running `init`. On
an enabled host the plugin also needs the Claude Code ACP bridge on PATH
(`npm i -g @agentclientprotocol/claude-agent-acp`) and a Claude Code login
(`claude setup-token`, or `CLAUDE_CODE_OAUTH_TOKEN`). It needs `neovim`: selected
without it, the sentinel is not created.

A component that is off is excluded two ways: its target files are added to
`.chezmoiignore` so `chezmoi apply` never writes them, and its plugin externals
are dropped from `.chezmoiexternal.toml` so they are never fetched. The base
files install regardless of selection: `~/.gitignore_global`, `~/.tfswitch.toml`,
and the tool linter configs (`~/.darglint`, `~/.flake8`, `~/.tflint.hcl`,
`~/.markdownlint.yaml`, `~/.config/yamllint/config`). Those linter configs are
plain tool configs, not neovim's, so they live at each tool's own path and
install even without the neovim component.

The raw answer is stored as `componentSelection` and parsed into
`[data.components]` booleans in `~/.config/chezmoi/chezmoi.toml`, reused on every
subsequent `chezmoi apply` without re-prompting.

## Changing components later

Two ways:

- Edit `~/.config/chezmoi/chezmoi.toml` directly and adjust the booleans:

  ```toml
  [data.components]
      zsh = true
      tmux = false
      neovim = true
      gitconfig = false
      codecompanion = false
  ```

- Or re-run the menu. `chezmoi init` will not re-prompt while
  `componentSelection` is set, so remove that line first, then re-init:

  ```sh
  sed -i.bak '/componentSelection/d' ~/.config/chezmoi/chezmoi.toml
  chezmoi init
  ```

Then run `chezmoi apply`. Turning a component off removes its files on the next
apply (its targets are now ignored); turning one on writes them and fetches its
plugins. Unmodified managed files are removed cleanly. A file you edited locally
is left in place rather than deleted, so back it up first if you want it gone.

## How it works

- **Content I author** (configs, custom functions, install scripts, docs)
  lives in this repo as regular files following chezmoi naming conventions
  (`dot_zshrc` -> `~/.zshrc`, `dot_zsh/aliases` -> `~/.zsh/aliases`, etc.).
- **Component selection** is a chezmoi-native concern. `.chezmoi.toml.tmpl`
  prompts once with a `promptStringOnce` numbered menu, parses the answer, and
  writes `[data.components]` into the per-host config. `.chezmoiignore` and
  `.chezmoiexternal.toml` are both templated off `.components.*`: an off
  component's targets are ignored and its externals are skipped.
- **Upstream plugins** are chezmoi externals (`.chezmoiexternal.toml`), fetched
  and refreshed by `chezmoi apply` on a weekly `refreshPeriod`. Only the
  selected components' externals are declared.
- **System packages** (zsh, neovim, tmux, fzf, gh, zoxide, etc.) are installed
  by `scripts/install-*.sh` on first apply. `run_once_after_00-install.sh`
  drives `scripts/install.sh` with the component selection passed as `INSTALL_*`
  env vars. One script per app plus a platform-aware orchestrator.

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
| `dot_config/nvim/lua/statusline.lua` | `~/.config/nvim/lua/statusline.lua` | |
| **Linter configs (base, each at its own path)** | | |
| `dot_darglint` | `~/.darglint` | docstring style |
| `dot_flake8` | `~/.flake8` | python style; `flake8` alias appends it |
| `dot_tflint.hcl` | `~/.tflint.hcl` | terraform lint rules |
| `dot_markdownlint.yaml` | `~/.markdownlint.yaml` | markdown rules; nvim-lint points `--config` here |
| `dot_config/yamllint/config` | `~/.config/yamllint/config` | yamllint's XDG config path |
| **System-level tool configs** | | |
| `dot_tfswitch.toml` | `~/.tfswitch.toml` | terraform version switcher |
| `gitconfig.example` | reference only | seed for `~/.gitconfig`; install.sh prompts to copy |
| `gitconfig.personal.example` | reference only | seed for `~/.gitconfig.personal`; fill in name/email |
| `dot_gitignore_global` | `~/.gitignore_global` | global ignore patterns |
| `.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | prompts for components at init; stores `[data.components]` |
| `.chezmoiignore` | (templated) | ignores an off component's target paths |
| `.chezmoiexternal.toml` | (templated externals) | plugins gated by `.components.zsh` / `.components.tmux` |

## Daily operation

```sh
# Edit a config file via chezmoi (so the source tree stays the source of truth):
chezmoi edit ~/.zshrc
chezmoi apply                      # materialize the edit into $HOME

# Or edit the source tree directly and then apply (~/dotfiles is a symlink to
# ~/.local/share/chezmoi, created by scripts/install.sh):
cd ~/dotfiles
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
rm -rf ~/.zsh ~/.tmux ~/.config/nvim ~/.config/yamllint ~/.local/share/nvim-venv
rm -f ~/.zshrc ~/.zshenv ~/.tmux.conf
rm -f ~/.darglint ~/.flake8 ~/.tflint.hcl ~/.markdownlint.yaml
rm -f ~/.gitignore_global ~/.tfswitch.toml
rm -f ~/dotfiles    # convenience symlink created by install.sh
```
