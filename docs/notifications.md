<!-- docs/notifications.md -->
# Notifications

## Table of Contents

- [Overview](#overview)
- [Configuration and rendering](#configuration-and-rendering)
- [Process notifications](#process-notifications)
- [Claude and Codex](#claude-and-codex)
- [Debugging](#debugging)
- [Dependencies](#dependencies)
- [Standalone install (no chezmoi)](#standalone-install-no-chezmoi)

## Overview

This subsystem marks a tmux pane when a long process finishes or an AI tool
needs attention. The visual cue is always present. Sound is optional per group,
and an empty sound disables it.

There are no notification-center popups. Outside tmux, the system deliberately
does nothing.

## Configuration and rendering

All behavior lives in `~/.config/notify/notify.yaml`. It contains group colors
and sounds, volume and duration thresholds, the command map, ignored commands,
and debug settings.

Each group has `bg`, `accent`, and `sound` values. `volume` and `threshold` can
be set globally or overridden by a group.

Entries under `groups` fire after a matching binary finishes. Claude and Codex
live under `integrations`, so their binaries are automatically excluded from
command detection. Starting `claude` should not immediately notify you about
starting Claude.

Named palette colors are rendered from `home/.chezmoidata/palettes.yaml`. Raw
`#hex` colors and `default` pass through unchanged. Edit behavior in the notify
template; edit shared colors in the palette catalog.

`~/.config/notify/lib.sh` contains the shared POSIX shell code for reading the
config, tinting panes, and playing sounds. It finds mikefarah `yq` and the real
tmux binary even with a stripped `PATH`, bypassing the Oh My Zsh tmux wrapper
and ignoring the incompatible kislyuk `yq`.

The lookup prefers `~/.local/bin/yq`, where the Debian installer puts the
mikefarah binary.

`~/.tmux/conf.d/notify.conf` renders the status flag and pane tint. A flagged
pane clears when it receives focus, keyboard input, a primary click, a drag, or
a scroll event. Right-click menus keep their normal tmux behavior.

New shells re-read the YAML. Reload tmux rendering with:

```sh
tmux source-file ~/.tmux.conf
```

## Process notifications

`~/.zsh/custom/functions/notify-process.zsh` reads the command map, thresholds,
and ignore list once during shell startup.

Its `preexec` and `precmd` hooks notify after a named binary, such as `terraform`
or `brew`, exceeds its group's threshold. The catch-all `default` group handles
other long-running commands. A failed command uses the `error` group.

## Claude and Codex

Claude Code calls `notify-tmux.sh` for `Stop`, `Notification`, and
`PreToolUse:AskUserQuestion` events. The matcher-less `Notification` event
covers permission prompts and idle state. `PreToolUse:AskUserQuestion` covers
the question tool, which does not emit a notification event.

The chezmoi `modify_` template at
`home/dot_claude/modify_settings.json.tmpl` merges these hooks into
`~/.claude/settings.json` without clobbering model, effort, or plugin settings.
Claude does not load `~/.claude/settings.local.json`, and `.claude` settings do
not merge up the directory tree. The external `~/.claude.json` remains
untouched.

Codex uses the same hook through `~/.codex/config.toml`. Its
`modify_private_config.toml.tmpl`, gated by
`ai > codex_hooks`, registers it for `agent-turn-complete`.

Codex does not send approval events to the external notify program. The merge
also enables its native `approval-requested` notification, but that alert is
currently ineffective under tmux. The upstream work is tracked in
[openai/codex#16855](https://github.com/openai/codex/issues/16855).

Restart Claude or Codex after changing their hook configuration.

## Debugging

Debug logging is off by default. Set `settings.debug: true` in the YAML or
export `NOTIFY_DEBUG=1`.

Events are written to `settings.log`, which defaults to
`~/.config/notify/notify.log`. The log caps itself at roughly 1 MB.

## Dependencies

The configuration uses [`yq`](https://github.com/mikefarah/yq) v4 from
mikefarah. It is installed whenever Zsh, tmux, Claude hooks, or Codex hooks need
the notification subsystem.

On macOS, the installer runs `brew install yq`. On Debian, it installs the
mikefarah binary under `~/.local/bin`.

Do not run `apt install yq` on Debian. That package is a different program with
incompatible syntax.

### Standalone install (no chezmoi)

To install only this subsystem on a machine without the full dotfiles, run:

```sh
scripts/install-notify.sh          # --force to overwrite an existing notify.yaml
```

The script copies the notify files, sounds, tmux renderer, and Claude hooks. It
installs mikefarah `yq` and wires `~/.zshrc`, `~/.tmux.conf`, and
`~/.claude/settings.json`.

If Codex is installed, the script also adds its hook and merges `notify` and
`tui.notifications` into `~/.codex/config.toml`, preserving mode 600.

The installer is idempotent. If `yq` is missing, it asks before installing it;
set `DOTFILES_ASSUME_YES=1` for an unattended run. Declining stops the install
instead of leaving a notification setup that cannot read its colors.

Do not run the standalone installer after `chezmoi apply`. That would load the
Zsh notifier twice, so the script refuses unless you pass `--force`.

Manual equivalent, if you prefer not to run the script:

1. `mkdir -p ~/.config/notify/sounds ~/.tmux/conf.d ~/.claude/hooks`
2. Render `home/dot_config/notify/notify.yaml.tmpl` as `notify.yaml`. Copy
   `lib.sh`, the clear helper, and sounds from `home/dot_config/notify/` into the
   matching notify directories. Copy `notify-process.zsh` from
   `home/dot_zsh/custom/functions/`. Copy `notify.conf` from
   `home/dot_tmux/conf.d/`, and copy the two notification hooks from
   `home/dot_claude/hooks/`. Remove the `executable_` prefix at their targets
   and mark the three helper scripts executable.
3. Install mikefarah `yq`: `brew install yq` (macOS) or fetch the `yq_linux_<arch>` binary to
   `~/.local/bin` (Debian; do **not** `apt install yq` - that is a different tool).
4. Add to `~/.zshrc`: `[ -f ~/.config/notify/notify-process.zsh ] && source ~/.config/notify/notify-process.zsh`
5. Add to `~/.tmux.conf`: `source-file ~/.tmux/conf.d/notify.conf` (this overrides
   `window-status-format` / `pane-border-format` - reconcile with your status bar).
6. Register the Claude hooks. The safest path is to let
   `scripts/install-notify.sh` render and run
   `home/dot_claude/modify_settings.json.tmpl`; it preserves existing settings.
   If doing this by hand, render that template with
   `data.components.ai.claude_hooks = true`, then run the generated modifier
   against `~/.claude/settings.json`.
7. Reload: `tmux source-file ~/.tmux.conf`, open a new shell, restart Claude Code.
