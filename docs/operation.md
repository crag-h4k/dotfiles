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
# Edit the source and apply it in one command:
chezmoi edit --apply ~/.zshrc

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

From a feature worktree, point chezmoi at that checkout explicitly:

```sh
cd /path/to/dotfiles-worktree
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

The repository-level `.chezmoiroot` still directs chezmoi into `home/`. It is
safe to review a worktree this way without replacing your normal source
directory.

## Terminal (tmux) behavior

`prefix + m` toggles tmux mouse capture. The two states trade tmux-native
selection against Ghostty-native selection:

| `prefix + m` | Behavior |
| --- | --- |
| on | tmux mouse capture: tmux drag-select and `tmux-yank` copy to the system clipboard with no Shift |
| off | Ghostty native selection across panes; this also disables tmux scroll and mouse pane-select until you toggle back (by design) |

Single-pane copy needs no toggle. Enter copy mode, drag to select, and press `y`
to copy. Mouse capture is on by default.

Use `prefix + m` for cross-pane native selection, when you want the terminal to
own the whole grid.

A wheel-up event always enters tmux copy mode, even when the foreground TUI has requested
application mouse reporting. Ghostty-over-SSH therefore scrolls tmux history instead of handing
the wheel to the TUI.

A flagged notification pane clears when it regains focus or receives ordinary
keyboard input, a primary click, a drag, or a scroll event. Only that pane is
cleared. Normal mouse behavior and right-click menus are left alone.

Session and window names are set automatically. `tmux ls` reads by project,
while window tabs read by task:

| Name | Source |
| --- | --- |
| Session | the project root (git toplevel basename, else cwd basename), set by a zsh `chpwd` hook (`home/dot_zsh/custom/functions/tmux-session-name.zsh`); a name you set manually via `prefix + $` is respected |
| Window | tracks the foreground command via tmux `automatic-rename` (`#{pane_current_command}`) |

So `tmux ls` shows project names while the window tabs show `1:zsh`, `2:nvim`, `3:git` live.

## Statusline (Claude / Codex)

The `ai > statusline` sub-feature installs a custom Claude Code statusline and a
matching Codex theme. It also installs `jq` and `python3`.

The renderer parses stdin with `jq`. A detached Python updater calculates the
subagent-inclusive token total away from the render path. Claude groups related
segments with a grey `│` and separates items inside a group with `·`:

| Group | Segments |
| --- | --- |
| identity | model; context (usage bar + percent, plus used/max at wider widths) |
| usage | cumulative token total (subagent-inclusive Sigma); session duration |
| limits | 5-hour and weekly rate bars |
| git | branch and dirty state |

Rate bars disappear when the payload has no `rate_limits`. Corporate and
enterprise Claude contracts commonly omit that field.

### Auto-width

Claude Code v2.1.153 and later exports `COLUMNS` and `LINES` to the statusline
command. Because stdout is captured, `tput cols` cannot inspect the terminal.
The stdin JSON has no width either, leaving `COLUMNS` as the useful signal.

The renderer uses it to widen bars or drop lower-priority segments:

| Tier | `COLUMNS` | Context bar | Rate bar | Drops |
| --- | --- | --- | --- | --- |
| wide | 115 or more | 16 | 12 | nothing |
| med | 80 to 114, or unset | 10 | 8 | nothing |
| narrow | 55 to 79 | 8 | 6 | used/max detail |
| tiny | under 55 | 6 | hidden | used/max, duration, rate bars |

When `COLUMNS` is unset, the renderer uses the `med` tier. This covers older
Claude versions, pipes, and non-interactive callers.

Bar widths, dropped segments, and divider glyphs are simple settings near the
top of `~/.claude/statusline-command.sh`.

Codex uses its native footer with the same selected palette. It shows model and
reasoning, run state, task progress, context use, session tokens, limits,
project root, and Git branch. Unavailable values are omitted.

The theme uses cyan for the model, pink for state, green for progress and
branch, purple for usage, orange for limits, and yellow for paths. It is
rendered to `~/.codex/themes/dotfiles.tmTheme`.

This is Codex's built-in `tui.status_line`, configured by the chezmoi merge
template. Codex does not currently support a command-backed footer, so it
cannot use Claude's custom glyphs, subagent token total, session duration, or
adaptive width tiers.

## Secret scanning

Mason installs Gitleaks for Neovim. Normal buffers are scanned asynchronously
after read and save. Findings are warning diagnostics and never block either
operation.

The official pinned pre-commit hook is the enforcement boundary:

```sh
pre-commit run gitleaks --all-files
```

See [Gitleaks](gitleaks.md) for exclusions, project allowlists, and
troubleshooting.

## Docker and Terraform checks

Neovim uses Docker's official language server for Dockerfiles and standard
Compose filenames. For repository checks, use the first-party validators and
Trivy:

```sh
docker build --check .
docker compose config --quiet
trivy config .
```

Terraform runs through tenv's project-aware proxy. It honors project version
files and `required_version`, installs missing versions, and verifies HashiCorp
signatures.

```sh
tenv tf install 1.15.7       # explicitly install a Terraform release
tenv tf use -w 1.15.7        # write .terraform-version in this project
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
tflint --init && tflint
trivy config .
```

The managed `~/.tflint.hcl` enables only TFLint's portable recommended rules.
Cloud-provider rulesets belong in each project; an AWS plugin has no business
loading in every Terraform repository.

## Supported platforms

| Platform | Package manager |
| --- | --- |
| macOS | Homebrew |
| Debian Trixie | `apt-get`, with sudo |

Headless CI deploys both rows from scratch. Ubuntu and other Linux
distributions may work when the listed binaries are installed, but they are not
deployment-gated.

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
