<!-- docs/architecture.md -->
# Architecture

## Table of Contents

- [How it works](#how-it-works)
- [What lives where](#what-lives-where)

## How it works

- **Content I author** (configs, custom functions, install scripts, docs) lives in this repo as
  regular files following chezmoi naming conventions (`dot_zshrc` -> `~/.zshrc`,
  `dot_zsh/aliases` -> `~/.zsh/aliases`, etc.).
- **Component selection** is a chezmoi-native concern. `.chezmoi.toml.tmpl` prompts at
  `chezmoi init` - a `gum` checkbox TUI when gum is on `PATH`, else a typed `promptStringOnce`
  numbered menu - parses the answer, and writes `[data.components]` (plus the nested `.git` /
  `.ai` sub-feature tables) into the per-host config. The `git` and `ai` components each open a
  second submenu for their sub-features. Both the gum options and the typed menu are generated
  from one `$components` list (with `$gitFeatures` / `$aiFeatures`) in that file.
  `.chezmoiignore` and `.chezmoiexternal.toml` are both templated off `.components.*` (down to
  `dig`-ing the sub-feature tables): an off component or sub-feature has its targets ignored and
  its externals skipped.
- **Upstream plugins** are chezmoi externals (`.chezmoiexternal.toml`), fetched and refreshed by
  `chezmoi apply` on a weekly `refreshPeriod`. Only the selected components' externals are
  declared.
- **Shared palette** data lives in `.chezmoidata/palettes.yaml`. Templates render the selected
  semantic colors into Ghostty, iTerm2, tmux, notify, Claude, and Codex; Neovim selects the
  corresponding pinned flavor. Consumers do not carry independent color copies.
- **System packages** are planned by `scripts/package-plan.sh`. The init template shows the
  deduped, source-grouped records before apply and saves `installMode`. `scripts/install.sh`
  consumes the same records for one Homebrew or apt batch plus the displayed cask, release,
  npm, pip, and LuaRocks work. It confirms before any package-manager mutation: a `[y/N]` prompt
  on the controlling terminal, or `DOTFILES_ASSUME_YES=1` to skip it. A decline (or a
  no-terminal apply with no opt-in) degrades to configs-only for that run and leaves `installMode`
  unchanged, so the choice never becomes sticky. Configs-only skips package and login-shell side
  effects.
- **The status-bar network indicator** (`↓ • ↑` throughput) comes from the
  `xamut/tmux-network-bandwidth` plugin (cross-platform, replaces the Linux-only
  `tmux-net-speed`). It needs `coreutils`+`gawk` on macOS and `gawk`+`net-tools` on Debian;
  those ride along in the tmux package set. It sums all interfaces, so VPN and VM-bridge traffic
  are included in the number.

## What lives where

| Path in repo | Target on host | Notes |
| --- | --- | --- |
| `dot_zshrc` | `~/.zshrc` | real file |
| `dot_zshenv` | `~/.zshenv` | real file |
| `dot_zsh/aliases` | `~/.zsh/aliases` | real file |
| `dot_zsh/bin/executable_*` | `~/.zsh/bin/*` | exec bit preserved |
| `dot_zsh/custom/functions/*.zsh` | `~/.zsh/custom/functions/*.zsh` | |
| `dot_zsh/custom/themes/gud.zsh-theme` | `~/.zsh/custom/themes/gud.zsh-theme` | default custom prompt; override with `data.zshTheme` |
| `dot_zsh/theme.zsh.tmpl` | `~/.zsh/theme.zsh` | resolves an Oh My Zsh theme name or readable theme path, with Gud fallback |
| `dot_tmux.conf` | `~/.tmux.conf` | real file; sources `notify.conf` (notify config moved to `notify.yaml`) |
| `dot_tmux/conf.d/*.conf` | `~/.tmux/conf.d/*.conf` | incl. `notify.conf` (status-bar flag + focus-clear) |
| `dot_config/notify/sounds/*.mp3` | `~/.config/notify/sounds/*.mp3` | notification audio files |
| `dot_config/notify/notify.yaml.tmpl` | `~/.config/notify/notify.yaml` | notify behavior plus colors rendered from the selected palette; gated on every notify consumer |
| `dot_config/notify/lib.sh` | `~/.config/notify/lib.sh` | shared `notify_fire`/`notify_clear`/`notify_play` + yq reader (array-free POSIX) |
| `dot_config/notify/executable_clear-pane.sh` | `~/.config/notify/clear-pane.sh` | clears one flagged pane from tmux keyboard and mouse bindings |
| `dot_claude/hooks/notify-tmux.sh` | `~/.claude/hooks/notify-tmux.sh` | Claude `Stop`/`Notification`/`PreToolUse:AskUserQuestion` hook; gated on `ai > claude_hooks` |
| `dot_claude/hooks/notify-clear.sh` | `~/.claude/hooks/notify-clear.sh` | Claude `UserPromptSubmit` hook (clears); gated on `ai > claude_hooks` |
| `dot_claude/modify_settings.json.tmpl` | `~/.claude/settings.json` (merge) | chezmoi `modify_` template: injects the notify hooks under `ai > claude_hooks` and asserts the `statusLine` command under `ai > statusline`, preserving your other settings |
| `dot_codex/hooks/notify-tmux.sh` | `~/.codex/hooks/notify-tmux.sh` | Codex `agent-turn-complete` notify hook (color+sound); gated on `ai > codex_hooks` |
| `dot_codex/modify_private_config.toml.tmpl` | `~/.codex/config.toml` (merge) | chezmoi `modify_` template: injects `notify` + `tui.notifications` under `ai > codex_hooks` and `tui.status_line` + `tui.theme` + `tui.status_line_use_colors` under `ai > statusline`, folded into a single `[tui]` table; preserves Codex's `[projects.*]` tables, keeps mode 600 |
| `dot_claude/executable_statusline-command.sh` | `~/.claude/statusline-command.sh` | Claude statusline renderer; gated on `ai > statusline` |
| `dot_claude/executable_statusline-tokens.py` | `~/.claude/statusline-tokens.py` | detached updater that walks the transcript + subagents for a token total; gated on `ai > statusline` |
| `dot_config/statusline/palette.sh.tmpl` | `~/.config/statusline/palette.sh` | semantic truecolor exports rendered from the selected palette |
| `dot_codex/themes/dotfiles.tmTheme.tmpl` | `~/.codex/themes/dotfiles.tmTheme` | selected-palette Codex theme, configured through `tui.theme="dotfiles"` |
| `dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | lazy.nvim entrypoint |
| `dot_config/nvim/lua/dotfiles_palette.lua.tmpl` | `~/.config/nvim/lua/dotfiles_palette.lua` | selected Neovim plugin, flavor, and colorscheme |
| `dot_config/nvim/lua/statusline.lua` | `~/.config/nvim/lua/statusline.lua` | |
| `dot_config/ghostty/themes/dotfiles.conf.tmpl` | `~/.config/ghostty/themes/dotfiles.conf` | selected terminal palette |
| `dot_config/iterm2/dotfiles.json.tmpl` | `~/.config/iterm2/dotfiles.json` | two Dynamic Profiles with generated palette colors |
| **Linter configs (base, each at its own path)** | | |
| `dot_darglint` | `~/.darglint` | docstring style |
| `dot_flake8` | `~/.flake8` | python style; `flake8` alias appends it |
| `dot_tflint.hcl` | `~/.tflint.hcl` | terraform lint rules |
| `dot_markdownlint.yaml` | `~/.markdownlint.yaml` | markdown rules; nvim-lint points `--config` here |
| `dot_config/yamllint/config` | `~/.config/yamllint/config` | yamllint's XDG config path |
| **System-level tool configs** | | |
| `dot_tfswitch.toml` | `~/.tfswitch.toml` | terraform version switcher |
| `gitconfig.example` | reference only | seed for `~/.gitconfig`; install.sh prompts to copy when `git > config` is on |
| `gitconfig.personal.example` | reference only | seed for `~/.gitconfig.personal`; copied when `git > personal` is on |
| `dot_gitignore_global` | `~/.gitignore_global` | global ignore patterns; gated on `git > ignore_global` (on by default) |
| `.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | prompts for components, palette, and install mode before apply |
| `.chezmoiignore` | (templated) | ignores an off component's (or sub-feature's) target paths |
| `.chezmoiexternal.toml` | (templated externals) | plugins gated by `.components.zsh` / `.components.tmux` |

The runtime token cache at `~/.cache/claude-statusline/` is not chezmoi-managed: the statusline
script creates it on demand and tolerates a wipe.
