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

Install `gum` first so the component picker shows a checkbox TUI, then
bootstrap chezmoi:

```sh
# macOS
command -v gum >/dev/null || brew install gum
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k

# Debian (gum not in standard apt; skip or install from charm repo)
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k
```

Without `gum` the picker falls back to a typed numbered menu - still works,
just less interactive.

The chezmoi bootstrap line:

1. Installs `chezmoi` if missing.
1. Clones this repo into `~/.local/share/chezmoi/`.
1. Prompts for which components to install (fzf TUI or typed menu) and saves
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
command -v gum >/dev/null || brew install gum   # macOS; skip on Debian (typed fallback)
chezmoi init crag-h4k      # clone + prompt for components
chezmoi apply              # write only the selected components
```

## Choosing components

With [`gum`](https://github.com/charmbracelet/gum) installed, `chezmoi init` shows a
checkbox TUI: space toggles a component, enter confirms, esc cancels. On re-runs
the header hints the current selection. `gum` is installed as part of the macOS base
toolchain on first apply (and is included in the bootstrap step above), so it is
available from the second `chezmoi init` onward (see
[Changing components later](#changing-components-later)).

Without `gum` - on Debian or if you skipped the bootstrap install - it falls back to a
typed numbered menu:

```text
Components to install:
  1) zsh       oh-my-zsh, plugins, custom functions, aliases
  2) tmux      tmux + plugins (tpm, resurrect, sensible, yank)
  3) neovim    neovim, lazy.nvim, language servers, linters
  4) gitconfig copy ~/.gitconfig* from repo examples
  5) ai        AI tools: CodeCompanion.nvim assistant (needs neovim)

Enter numbers (e.g. "1 3"), all, all+, or press Enter for default (1 2 3):
```

Both paths resolve to the same `componentSelection` string and the same
`[data.components]` booleans. For the typed menu:

- Numbers: any subset (e.g. `1 3` for zsh + neovim). Spacing and order do not
  matter - `1 3`, `13`, and `3 1` are equivalent.
- Enter: the default, `1 2 3` (zsh + tmux + neovim; no gitconfig, no AI tools).
- `all`: zsh + tmux + neovim.
- `all+`: everything including gitconfig and the AI tools.

The component list is the single source of truth in `.chezmoi.toml.tmpl`; the gum
options and the typed menu are both generated from it, so adding a component is a
one-line edit there. Set `DOTFILES_NO_TUI=1` to force the typed menu even when gum
is installed.

The `ai` component is one opt-in toggle for AI tooling (off in the default set and
in `all`), so nothing AI-related installs unless you ask for it. With `neovim` it
enables CodeCompanion: the assistant ships buffer contents to an LLM, so a sentinel
file (`~/.config/nvim/.codecompanion-enabled`) gates the plugin at startup; you can
`touch`/`rm` it to flip per-host without re-running `init`. The Claude Code ACP
bridge (`claude-agent-acp`) is installed via npm into `~/.local/bin`, and the chat
reuses your existing `claude` login (no token to store). Selected without `neovim`,
it is a no-op.

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

- Re-open the picker. The `ccomp` alias runs `chezmoi init --apply`:

  ```sh
  ccomp     # alias for: chezmoi init --apply
  ```

  With `gum` installed (it is, after the first macOS apply) this re-opens the gum
  TUI with the current selection hinted, then applies. The gum picker is not
  gated by `promptStringOnce`, so it re-prompts every time - no need to clear
  `componentSelection` first. Cancelling the picker (Esc) keeps the current
  selection unchanged.

  Without `gum`, `chezmoi init` falls back to `promptStringOnce`, which will not
  re-prompt while `componentSelection` is set; clear it first, then re-init:

  ```sh
  sed -i.bak '/componentSelection/d' ~/.config/chezmoi/chezmoi.toml
  chezmoi init --apply
  ```

- Or edit `~/.config/chezmoi/chezmoi.toml` directly and adjust the booleans,
  then `chezmoi apply`:

  ```toml
  [data.components]
      zsh = true
      tmux = false
      neovim = true
      gitconfig = false
      ai = false
  ```

Turning a component off removes its files on the next apply (its targets are now
ignored); turning one on writes them and fetches its plugins. Unmodified managed
files are removed cleanly. A file you edited locally is left in place rather than
deleted, so back it up first if you want it gone.

Enabling a component that installs packages (e.g. `ai`) also re-runs the
installer automatically: `run_once_after_00-install.sh` embeds the component
booleans, so flipping one changes the script's rendered content and chezmoi
re-runs it on the next apply, installing the newly selected tools. If it does not
re-run for some reason, force it:

```sh
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

So to enable the AI tools after the fact: set `ai = true` in
`~/.config/chezmoi/chezmoi.toml` (or re-run the menu and include `5`), then
`chezmoi apply`. That installs the Claude Code ACP bridge and provisions the
CodeCompanion sentinel - no full reinstall needed.

## How it works

- **Content I author** (configs, custom functions, install scripts, docs)
  lives in this repo as regular files following chezmoi naming conventions
  (`dot_zshrc` -> `~/.zshrc`, `dot_zsh/aliases` -> `~/.zsh/aliases`, etc.).
- **Component selection** is a chezmoi-native concern. `.chezmoi.toml.tmpl`
  prompts at `chezmoi init` - a `gum` checkbox TUI when gum is on `PATH`,
  else a typed `promptStringOnce` numbered menu - parses the answer, and writes
  `[data.components]` into the per-host config. Both the gum options and the typed
  menu are generated from one `$components` list in that file. `.chezmoiignore`
  and `.chezmoiexternal.toml` are both templated off `.components.*`: an off
  component's targets are ignored and its externals are skipped.
- **Upstream plugins** are chezmoi externals (`.chezmoiexternal.toml`), fetched
  and refreshed by `chezmoi apply` on a weekly `refreshPeriod`. Only the
  selected components' externals are declared.
- **System packages** (zsh, neovim, tmux, fzf, gh, zoxide, gum, etc.) are installed
  by `scripts/install.sh` on first apply. All packages for selected components
  are batched into one `brew install` / `apt-get install -y` call per OS.
  `run_once_after_00-install.sh` drives `install.sh` with the component selection
  passed as `INSTALL_*` env vars.

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
