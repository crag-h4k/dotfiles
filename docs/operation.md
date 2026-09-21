<!-- docs/operation.md -->
# Operation

## Table of Contents

- [Daily operation](#daily-operation)
- [Local overrides](#local-overrides)
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

# Force a direct fast-forward-only external refresh. Routine safe updates use
# cup, which also skips dirty and diverged checkouts before pulling:
chezmoi apply --refresh-externals

# Re-run package provisioning without deleting chezmoi script state. This
# opens the package plan and mode confirmation. Selecting packages advances the
# persisted packageRun trigger and reruns only the content-hashed installer:
cup

# Run the same update without a TTY. All three opt-ins are required:
DOTFILES_PACKAGE_UPDATE=1 DOTFILES_INSTALL_MODE=packages \
  DOTFILES_ASSUME_YES=1 chezmoi init --apply --no-tty

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

## Local overrides

Each managed tool reads one unmanaged file where you can change its behavior
without editing the config in this repo. Adopt these dotfiles, drop your
settings in these files, and `chezmoi update` keeps working:

- Ghostty: `~/.config/ghostty/override.conf`
- tmux: `~/.tmux/conf.d/override.conf`
- Zsh: `~/.zsh_override`
- Neovim: `~/.config/nvim/lua/override.lua`
- Git: `~/.gitconfig.override`

None are chezmoi-managed. Each is listed
unconditionally in `home/.chezmoiignore`, so chezmoi never applies or removes
them, and `chezmoi add` and `chezmoi re-add` refuse them. Your settings stay
yours and never reach this public repo. The installer creates an empty mode-600
Git override only when managed Git config is selected and the file is absent.

Every include is optional. Ghostty
uses the `?` path prefix, tmux uses `source-file -q`, Git silently skips a
missing include, Zsh uses an `[[ -r ]]` guard, and Neovim uses a guarded
`pcall`. Delete a file and the tool starts clean.

Each override loads after its managed base. Most load at the absolute end. tmux
loads its override before the managed plugin list and the final TPM command so
local plugin declarations and options exist before plugin startup.

```text
# ~/.config/ghostty/override.conf
font-size = 14
```

```zsh
# ~/.zsh_override
alias ll='eza -l'
export EDITOR=vim
```

### Git identities

The managed Git config contains no name, email, signing key, or private path.
It sets `user.useConfigOnly = true` and includes `~/.gitconfig.override` last.

Git cannot nest `[user]` values under `includeIf`; conditional includes can only
name another file. To keep one private file, define aliases that write identity
settings into the current repository's local `.git/config`:

```gitconfig
# ~/.gitconfig.override
[alias]
    identity-personal = "!f() { git config --local user.name 'Personal Name'; git config --local user.email 'personal@example.invalid'; }; f"
    identity-work = "!f() { git config --local user.name 'Work Name'; git config --local user.email 'work@example.invalid'; }; f"
```

Run `git identity-personal` or `git identity-work` once after cloning. Add local
`user.signingKey`, `gpg.format`, and `commit.gpgSign` commands to either alias if
that identity signs commits.

The former `~/.config/git/override.conf` is no longer loaded. Migrate any useful
settings into `~/.gitconfig.override`; the old file remains ignored and is not
deleted automatically.

### tmux plugins

Disable default plugins independently by setting their switches to `off`:

```tmux
# ~/.tmux/conf.d/override.conf
set -g @dotfiles_plugin_tmux_cpu off
set -g @dotfiles_plugin_tmux_network_bandwidth off
```

All five switches default to `on`:

| Switch | Default plugin |
| --- | --- |
| `@dotfiles_plugin_tmux_sensible` | `tmux-plugins/tmux-sensible` |
| `@dotfiles_plugin_tmux_yank` | `tmux-plugins/tmux-yank` |
| `@dotfiles_plugin_tmux_cpu` | `tmux-plugins/tmux-cpu` |
| `@dotfiles_plugin_tmux_network_bandwidth` | `xamut/tmux-network-bandwidth` |
| `@dotfiles_plugin_tmux_resurrect` | `tmux-plugins/tmux-resurrect` |

TPM itself has no switch because it initializes the selected default plugins
and every local addition. Add a plugin with TPM's standard literal syntax. Put
its options before the declaration when the plugin reads them at startup:

```tmux
# ~/.tmux/conf.d/override.conf
set -g @continuum-restore 'on'
set -g @plugin 'tmux-plugins/tmux-continuum'
```

Reload tmux, then use `prefix + I` to install a local addition. TPM owns plugins
declared only in `override.conf`. Its package bindings are scoped accordingly:

| Binding | Scope |
| --- | --- |
| `prefix + I` | Install missing local plugins |
| `prefix + U` | Update one named local plugin, or every local plugin with `all` |
| `prefix + M-u` | Remove unused local plugin directories |

The wrapper refuses to update default names and protects every default checkout
during interactive TPM clean, including disabled plugins. Approved package mode
installs or fast-forwards TPM and the five default plugin repositories. Chezmoi
ignores the complete `~/.tmux/plugins` runtime tree and does not lock or track it.

TPM sees one combined plugin set during startup. Enabled defaults use
its runtime `@tpm_plugins` option, while local literal `@plugin` lines come from
TPM's static scan of sourced files. The final startup command then replaces the
package bindings with the local-only wrapper.

`@tpm_plugins` is deprecated upstream but remains supported. The managed config
rebuilds that option after `override.conf`, so do not set it yourself. Local
additions must use a one-line literal `set -g @plugin 'owner/repo'` declaration;
TPM does not discover a repository assembled through a variable or conditional.
Do not repeat a default repository as a local `@plugin`, or TPM can start it
twice.

TPM prefers `$XDG_CONFIG_HOME/tmux/tmux.conf` when that file exists. A separate
XDG main config can therefore hide this repository's `~/.tmux.conf` and its
sourced override from TPM's static scanner. Keep `~/.tmux.conf` as the active
main config when using this override path.

Disabling a plugin prevents it from starting in a fresh tmux server. Reloading
`~/.tmux.conf` in an existing server does not undo options, hooks, or bindings
that the plugin already installed. End the existing server and start a new one
for a disable to take full effect.

### Ordering

Ghostty defers included files until after the config that names them, so its
`config-file` line can sit anywhere. Zsh, Git, Neovim, and tmux load inline. The
first three keep their override at the bottom of the managed config.

tmux uses this sequence:

| Phase | Action |
| --- | --- |
| 1 | Load managed tmux options and `conf.d` files |
| 2 | Source optional `~/.tmux/conf.d/override.conf` |
| 3 | Rebuild enabled managed defaults in `@tpm_plugins` |
| 4 | Run TPM as the final executable line in `~/.tmux.conf` |

Plugin-specific options and local literal `@plugin` declarations are therefore
available when TPM starts plugins. This ordering is intended for options that a
plugin reads as input. Generic settings that a plugin unconditionally writes are
not guaranteed to be last-wins because the plugin starts after `override.conf`.
Use the plugin's documented options instead.

Neovim has the same shape. The `pcall` runs after `require("lazy").setup()`
returns, so `override.lua` covers options, keymaps, autocmds, and per-machine
LSP paths, but cannot add lazy plugins and cannot beat a lazy-loaded plugin's
own config, which runs on demand later. Use a spec import or an autocmd for
those.

Git applies includes inline too, so the override include is last in
`~/.gitconfig`. Verify with `git config --list --includes --global`, not
`--get`: `--includes` defaults off when a file scope like `--global` is given,
so `--get` silently reports the pre-include value.

### `~/.zsh_override` vs `~/.zsh_private`

Two files, two jobs:

- `~/.zsh_override` is for changing this config. Aliases, functions, options,
  keybinds, completion. `.zshrc` sources it last, so it beats the managed
  aliases, Oh My Zsh, and the custom functions.
- `~/.zsh_private` is for credentials, private env vars, and work-specific
  settings. `.zshrc` creates it on first run and sources it early, so the
  aliases and functions loaded afterwards can use what it defines.

Local shell functions belong in `~/.zsh_override` rather than
`$ZSH_CUSTOM/functions/`, which `.zshrc` globs and chezmoi manages. A blanket
ignore there would un-manage the real function files, so anything you do drop in
that directory should be named `local-*.zsh`, which `.chezmoiignore` guards.

### Backups

`run_before_00-backup.sh` skips `$HOME` itself but sweeps every directory that
holds a managed file. The hatches under `.config/` and `.tmux/` are therefore
copied in plaintext into `~/.dotfiles-backup/`, with 20 snapshots retained.
`~/.zsh_override` and `~/.zsh_private` sit loose in `$HOME` and are never swept,
which is the right place for anything sensitive.

### Reloading

```sh
ghostty +validate-config          # then reload Ghostty's config
tmux source-file ~/.tmux.conf
exec zsh
git config --list --includes --global
```

The tmux reload applies new configuration but cannot tear down state left by an
already-loaded plugin. Restart the tmux server after disabling a plugin.

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
