<!-- docs/architecture.md -->
# Architecture

## Table of Contents

- [How it works](#how-it-works)
- [What lives where](#what-lives-where)

## How it works

- **Managed content** lives under `home/`, selected by the repository-level `.chezmoiroot`.
  Files there follow chezmoi naming conventions (`home/dot_zshrc` -> `~/.zshrc`,
  `home/dot_zsh/aliases` -> `~/.zsh/aliases`, etc.). Project scripts, tests, docs, workflows,
  linter policy, and `vendor/` stay outside that source root and therefore cannot become host
  targets accidentally.
- **Component selection** is a chezmoi-native concern. `home/.chezmoi.toml.tmpl` prompts at
  `chezmoi init` - a `gum` checkbox TUI when gum is on `PATH`, else a typed `promptStringOnce`
  numbered menu - parses the answer, and writes `[data.components]` (plus the nested `.git` /
  `.ai` sub-feature tables) into the per-host config. The `git` and `ai` components each open a
  second submenu for their sub-features. Both the gum options and the typed menu are generated
  from one `$components` list (with `$gitFeatures` / `$aiFeatures`) in that file.
  `home/.chezmoiignore` and `home/.chezmoiexternal.toml` are both templated off `.components.*` (down to
  `dig`-ing the sub-feature tables): an off component or sub-feature has its targets ignored and
  its externals skipped.
- **Upstream plugins** are chezmoi externals (`home/.chezmoiexternal.toml`), fetched and refreshed by
  `chezmoi apply` on a weekly `refreshPeriod`. Only the selected components' externals are
  declared.
- **Shared palette** data lives in `home/.chezmoidata/palettes.yaml`. Templates render the selected
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
- **Development toolchain.** The cross-platform Neovim package plan owns shell-visible
  markdownlint-cli2, ShellCheck, yamllint, TFLint, Trivy, and Luacheck. Mason owns the desired
  language-server set and editor-only Gitleaks, installing only packages that are absent rather
  than updating or reconciling installed versions. On Debian, NodeSource and Aqua Security are
  explicit signed apt sources; TFLint and tenv release archives are checksum-verified before
  their binaries are installed. tenv's `terraform` proxy selects project versions and verifies
  HashiCorp signatures.
- **The status-bar network indicator** (`↓ • ↑` throughput) comes from the
  `xamut/tmux-network-bandwidth` plugin (cross-platform, replaces the Linux-only
  `tmux-net-speed`). It needs `coreutils`+`gawk` on macOS and `gawk`+`net-tools` on Debian;
  those ride along in the tmux package set. It sums all interfaces, so VPN and VM-bridge traffic
  are included in the number.

## What lives where

| Path in repo | Target on host | Notes |
| --- | --- | --- |
| `home/dot_zshrc` | `~/.zshrc` | real file |
| `home/dot_zshenv` | `~/.zshenv` | real file |
| `home/dot_zsh/aliases` | `~/.zsh/aliases` | real file |
| `home/dot_zsh/bin/executable_*` | `~/.zsh/bin/*` | exec bit preserved |
| `home/dot_zsh/custom/functions/*.zsh` | `~/.zsh/custom/functions/*.zsh` | |
| `home/dot_zsh/custom/themes/gud.zsh-theme` | `~/.zsh/custom/themes/gud.zsh-theme` | default custom prompt; override with `data.zshTheme` |
| `home/dot_zsh/theme.zsh.tmpl` | `~/.zsh/theme.zsh` | resolves an Oh My Zsh theme name or readable theme path, with Gud fallback |
| `home/dot_tmux.conf` | `~/.tmux.conf` | real file; sources `notify.conf` (notify config moved to `notify.yaml`) |
| `home/dot_tmux/conf.d/*.conf` | `~/.tmux/conf.d/*.conf` | incl. `notify.conf` (status-bar flag + focus-clear) |
| `home/dot_config/notify/sounds/*.mp3` | `~/.config/notify/sounds/*.mp3` | notification audio files |
| `home/dot_config/notify/notify.yaml.tmpl` | `~/.config/notify/notify.yaml` | notify behavior plus colors rendered from the selected palette; gated on every notify consumer |
| `home/dot_config/notify/lib.sh` | `~/.config/notify/lib.sh` | shared `notify_fire`/`notify_clear`/`notify_play` + yq reader (array-free POSIX) |
| `home/dot_config/notify/executable_clear-pane.sh` | `~/.config/notify/clear-pane.sh` | clears one flagged pane from tmux keyboard and mouse bindings |
| `home/dot_claude/hooks/notify-tmux.sh` | `~/.claude/hooks/notify-tmux.sh` | Claude `Stop`/`Notification`/`PreToolUse:AskUserQuestion` hook; gated on `ai > claude_hooks` |
| `home/dot_claude/hooks/notify-clear.sh` | `~/.claude/hooks/notify-clear.sh` | Claude `UserPromptSubmit` hook (clears); gated on `ai > claude_hooks` |
| `home/dot_claude/modify_settings.json.tmpl` | `~/.claude/settings.json` (merge) | chezmoi `modify_` template: injects the notify hooks under `ai > claude_hooks` and asserts the `statusLine` command under `ai > statusline`, preserving your other settings |
| `home/dot_codex/hooks/notify-tmux.sh` | `~/.codex/hooks/notify-tmux.sh` | Codex `agent-turn-complete` notify hook (color+sound); gated on `ai > codex_hooks` |
| `home/dot_codex/modify_private_config.toml.tmpl` | `~/.codex/config.toml` (merge) | chezmoi `modify_` template: injects `notify` + `tui.notifications` under `ai > codex_hooks` and `tui.status_line` + `tui.theme` + `tui.status_line_use_colors` under `ai > statusline`, folded into a single `[tui]` table; preserves Codex's `[projects.*]` tables, keeps mode 600 |
| `home/dot_claude/executable_statusline-command.sh` | `~/.claude/statusline-command.sh` | Claude statusline renderer; gated on `ai > statusline` |
| `home/dot_claude/executable_statusline-tokens.py` | `~/.claude/statusline-tokens.py` | detached updater that walks the transcript + subagents for a token total; gated on `ai > statusline` |
| `home/dot_config/statusline/palette.sh.tmpl` | `~/.config/statusline/palette.sh` | semantic truecolor exports rendered from the selected palette |
| `home/dot_codex/themes/dotfiles.tmTheme.tmpl` | `~/.codex/themes/dotfiles.tmTheme` | selected-palette Codex theme, configured through `tui.theme="dotfiles"` |
| `home/dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | lazy.nvim entrypoint |
| `home/dot_config/nvim/lua/dotfiles_palette.lua.tmpl` | `~/.config/nvim/lua/dotfiles_palette.lua` | selected Neovim plugin, flavor, and colorscheme |
| `home/dot_config/nvim/lua/gitleaks.lua` | `~/.config/nvim/lua/gitleaks.lua` | asynchronous read/save secret warnings; honors project `.gitleaks.toml` |
| `home/dot_config/nvim/lua/statusline.lua` | `~/.config/nvim/lua/statusline.lua` | |
| `home/dot_config/ghostty/themes/dotfiles.conf.tmpl` | `~/.config/ghostty/themes/dotfiles.conf` | selected terminal palette |
| `home/dot_config/iterm2/dotfiles.json.tmpl` | `~/.config/iterm2/dotfiles.json` | two Dynamic Profiles with generated palette colors |
| **Linter configs (base, each at its own path)** | | |
| `home/dot_darglint` | `~/.darglint` | docstring style |
| `home/dot_flake8` | `~/.flake8` | python style; `flake8` alias appends it |
| `home/dot_tflint.hcl` | `~/.tflint.hcl` | terraform lint rules |
| `home/dot_markdownlint.yaml` | `~/.markdownlint.yaml` | markdown rules; nvim-lint points `--config` here |
| `home/dot_config/yamllint/config` | `~/.config/yamllint/config` | yamllint's XDG config path |
| `home/dot_gitconfig` | `~/.gitconfig` | shared Git behavior and credential helpers; gated on `git > config` |
| `home/private_dot_gitconfig.personal.tmpl` | `~/.gitconfig.personal` | per-host name/email rendered from private chezmoi data with mode 600; gated on `git > personal` |
| `home/dot_gitignore_global` | `~/.gitignore_global` | global ignore patterns; gated on `git > ignore_global` (on by default) |
| `home/.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | prompts for components, palette, and install mode before apply |
| `home/.chezmoiignore` | (templated) | ignores an off component's (or sub-feature's) target paths |
| `home/.chezmoiexternal.toml` | (templated externals) | plugins gated by `.components.zsh` / `.components.tmux` |
| `home/.chezmoiscripts/run_before_00-backup.sh` | apply hook | snapshots existing targets before changes |
| `home/.chezmoiscripts/run_once_after_00-install.sh.tmpl` | apply hook | delegates package/config setup to the project scripts |

Repository-only lint policy lives under `config/linters/` (`gitleaks.toml`,
`luacheckrc`, `markdownlint.yaml`, and `stylua.toml`). Pre-commit passes those
paths explicitly, keeping project validation separate from the similarly named
configs that chezmoi installs into a host's home directory.

The runtime token cache at `~/.cache/claude-statusline/` is not chezmoi-managed: the statusline
script creates it on demand and tolerates a wipe.
