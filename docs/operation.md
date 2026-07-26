<!-- docs/operation.md -->
# Operation

## Table of Contents

- [Daily operation](#daily-operation)
- [Terminal (tmux) behavior](#terminal-tmux-behavior)
- [Statusline (Claude / Codex)](#statusline-claude--codex)
- [Secret scanning](#secret-scanning)
- [Docker and Terraform checks](#docker-and-terraform-checks)
- [Supported platforms](#supported-platforms)
- [Uninstall](#uninstall)

## Daily operation

```sh
# Edit a config file via chezmoi (so the source tree stays the source of truth):
chezmoi edit ~/.zshrc
chezmoi apply                      # materialize the edit into $HOME

# Or edit the source tree directly and then apply (~/dotfiles is a symlink to
# ~/.local/share/chezmoi, created by scripts/install.sh):
cd ~/dotfiles
$EDITOR home/dot_zshrc
chezmoi apply

# Pull upstream plugins now instead of waiting for weekly refresh:
chezmoi apply --refresh-externals

# Re-run the install scripts (e.g. after updating packages). This recipe and
# flipping a component both prompt [y/N] before touching a package manager;
# answer N to apply configs only, or skip the prompt with DOTFILES_ASSUME_YES=1:
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
DOTFILES_ASSUME_YES=1 chezmoi apply   # unattended: install without prompting

# Inspect what chezmoi thinks should change:
chezmoi diff

# Sync chezmoi source with this repo's origin:
chezmoi update                     # git pull in source + apply
```

## Terminal (tmux) behavior

`prefix + m` toggles tmux mouse capture. The two states trade tmux-native selection against
Ghostty-native selection:

| `prefix + m` | Behavior |
| --- | --- |
| on | tmux mouse capture: tmux drag-select and `tmux-yank` copy to the system clipboard with no Shift |
| off | Ghostty native selection across panes; this also disables tmux scroll and mouse pane-select until you toggle back (by design) |

Single-pane copy needs no toggle: enter copy-mode, drag to select, and `y` copies (tmux mouse is
on by default). `prefix + m` is only for cross-pane native selection, when you want the terminal
to own the whole grid.

A wheel-up event always enters tmux copy mode, even when the foreground TUI has requested
application mouse reporting. Ghostty-over-SSH therefore scrolls tmux history instead of handing
the wheel to the TUI.

A flagged notify pane clears when it regains focus or receives ordinary keyboard input, a
primary click, a drag, or a scroll event. The binding targets only the receiving pane, preserves
normal and copy-mode mouse behavior, and leaves right-click menus untouched.

Session and window names are set automatically so `tmux ls` reads by project while the window
tabs read by task:

| Name | Source |
| --- | --- |
| Session | the project root (git toplevel basename, else cwd basename), set by a zsh `chpwd` hook (`home/dot_zsh/custom/functions/tmux-session-name.zsh`); a name you set manually via `prefix + $` is respected |
| Window | tracks the foreground command via tmux `automatic-rename` (`#{pane_current_command}`) |

So `tmux ls` shows project names while the window tabs show `1:zsh`, `2:nvim`, `3:git` live.

## Statusline (Claude / Codex)

The `ai > statusline` sub-feature installs the custom statusline renderer for Claude Code and a
matching selected-palette theme for Codex. Enabling it also pulls `jq` and `python3` as runtime deps: the
renderer parses its stdin JSON with `jq`, and a detached `python3` updater refreshes the
subagent-inclusive token total off the render path. The Claude statusline clusters its segments
into groups joined by a grey `│`; items inside a group are joined by a grey `·`:

| Group | Segments |
| --- | --- |
| identity | model; context (usage bar + percent, plus used/max at wider widths) |
| usage | cumulative token total (subagent-inclusive Sigma); session duration |
| limits | 5-hour and weekly rate bars |
| git | branch and dirty state |

The rate bars auto-hide when `rate_limits` is absent from the payload. Corporate and enterprise
Claude contracts carry no `rate_limits`, so the 5-hour and weekly bars will typically not appear.

### Auto-width

Claude Code (v2.1.153+) exports `COLUMNS` and `LINES` to the statusline command. Its stdout is
captured, so `tput cols` cannot read the terminal, and the stdin JSON carries no width, which
leaves `COLUMNS` as the only width signal. The renderer reads it and picks a layout tier, widening
the bars when there is room and dropping lower-priority segments when space is tight:

| Tier | `COLUMNS` | Context bar | Rate bar | Drops |
| --- | --- | --- | --- | --- |
| wide | 115 or more | 16 | 12 | nothing |
| med | 80 to 114, or unset | 10 | 8 | nothing |
| narrow | 55 to 79 | 8 | 6 | used/max detail |
| tiny | under 55 | 6 | hidden | used/max, duration, rate bars |

When `COLUMNS` is unset (an older Claude Code, a pipe, a non-interactive caller) the renderer
falls back to the `med` tier, which mirrors the previous fixed layout. The per-tier bar widths,
the segment drops, and the divider glyphs are one-line tunables near the top of
`~/.claude/statusline-command.sh`.

Codex uses its native footer with the same selected palette. The configured order is model and
reasoning, run-state, active task progress, context use, session tokens, 5-hour and weekly limits,
project root, and Git branch. Unavailable values are omitted automatically. The palette gives each
field family a distinct accent through `~/.codex/themes/dotfiles.tmTheme`: cyan model, pink state,
green progress and branch, purple usage, orange limits, and yellow paths.

This is Codex's built-in `tui.status_line`, configured by the chezmoi merge template. Codex does
not currently support a command-backed footer, so it cannot use the Claude renderer's custom
glyphs, subagent token total, session duration, or adaptive width tiers.

## Secret scanning

Mason installs Gitleaks for Neovim only. Normal file buffers are scanned asynchronously after
read and save; findings appear as warning diagnostics and never block either operation. Plugin,
dependency, generated-state, and special buffers are excluded. A project-root `.gitleaks.toml`
is passed explicitly when present, so project allowlists apply to editor scans. The dotfiles
repo's own policy extends the Gitleaks defaults and allowlists only its vendored and binary media
assets.

The official pinned pre-commit hook is the enforcement boundary. It scans staged changes with
redaction enabled, while the editor integration is intentionally advisory:

```sh
pre-commit run gitleaks --all-files
```

## Docker and Terraform checks

Neovim uses Docker's official language server for Dockerfiles and standard Compose filenames.
For repository checks, use the first-party validators and Trivy:

```sh
docker build --check .
docker compose config --quiet
trivy config .
```

Terraform is exposed through tenv's project-aware `terraform` proxy. It honors project version
files and `required_version`, automatically installs a missing version, and verifies HashiCorp's
checksum signature. Common operations are:

```sh
tenv tf install 1.15.7       # explicitly install a Terraform release
tenv tf use -w 1.15.7        # write .terraform-version in this project
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --init && tflint
trivy config .
```

The managed `~/.tflint.hcl` enables only TFLint's portable recommended Terraform rules.
Cloud-provider rulesets belong in each project so an AWS plugin is not loaded for every
Terraform repository.

## Supported platforms

| Platform | Package manager |
| --- | --- |
| macOS | Homebrew |
| Debian / Ubuntu | `apt-get`, with sudo |

Other Linux distros work if you install the listed binaries yourself; the config is
distro-agnostic.

## Uninstall

```sh
chezmoi purge          # removes chezmoi source and state
rm -rf ~/.zsh ~/.tmux ~/.config/nvim ~/.config/yamllint ~/.local/share/nvim-venv
rm -f ~/.zshrc ~/.zshenv ~/.tmux.conf
rm -f ~/.darglint ~/.flake8 ~/.tflint.hcl ~/.markdownlint.yaml
rm -f ~/.gitignore_global ~/.local/bin/tenv ~/.local/bin/terraform ~/.local/bin/tflint
rm -rf ~/.tenv
rm -f ~/dotfiles    # convenience symlink created by install.sh
```
