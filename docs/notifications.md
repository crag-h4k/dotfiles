<!-- docs/notifications.md -->
# Notifications

## Table of Contents

- [Overview](#overview)
- [Configuration and rendering](#configuration-and-rendering)
- [Process notifications](#process-notifications)
- [Claude and Codex](#claude-and-codex)
- [OpenCode](#opencode)
- [Debugging](#debugging)
- [Dependencies](#dependencies)
- [Standalone install (no chezmoi)](#standalone-install-no-chezmoi)

## Overview

This subsystem marks a tmux pane when a long process finishes or an AI tool
needs attention. The visual cue is present for every tmux notification except
one OpenCode case, described under [OpenCode](#opencode). Sound is optional per
group, and an empty sound disables it.

There are no notification-center popups. Outside tmux, the process notifier, the
Claude and Codex hooks, and the OpenCode bridge deliberately do nothing. The one
outside-tmux sound is OpenCode's own attention sound, which the `opencode2`
wrapper configures from this file.

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

`~/.tmux/conf.d/notify.conf` renders the status flag and pane tint. Pane flags
never inherit the window-tab flag, so notifying one pane in a split window does
not mark its neighbors. The window tab stays flagged until every flagged pane
in that window has cleared. Keyboard input or a mouse-button press clears the
targeted pane; focus changes and scrolling do not. Alt+right-click retains the
tmux pane menu.

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

## OpenCode

OpenCode has no hook mechanism, so the bridge is a plugin:
`~/.config/opencode/plugin/notify.ts`. Its native V2 `setup()` export subscribes
to the public server event stream.

The plugin shells out to `~/.config/notify/opencode-events.sh`, which takes the
verb and a group name.

Unlike Claude and Codex, OpenCode splits attention into three groups, so the
pane color says what it is waiting for:

- `opencode` fires when the interactive session finishes, on
  `session.execution.succeeded`. Child-session completions do not flag its pane.
- `opencode_permission` fires when a tool is blocked on manual approval, on
  `permission.asked`. Auto's terminal session-workflow plugin owns its approval
  attempts and notifies only after an attempt fails and the request still needs
  an answer. Slow successful approvals stay silent. A failed request in another
  session does not flag the current pane.
- `opencode_question` fires when the agent asks a question and cannot continue
  until you answer, on `form.created`. Integration auth forms reuse the
  same event and also block, so they notify too.

An older asynchronous notification check cannot replace a newer attention cue.
Auto permission alerts require the managed session-workflow terminal plugin to
be loaded. Custom shared-service notification bridges must also skip automatic
permission asks; their independent event handlers are not managed here.

Every one of those names was confirmed by subscribing a probe plugin to a live
session. Do not add events from the SDK type union without observing them first.
The union advertises other event names that were not emitted by the tested V2
build. The question case uses the observed `form.created` event rather than an
unverified `question.*` name.

Two mistakes here fail silently, and both are guarded:

- **The child gets reaped.** Attention events arrive at the moment OpenCode tears
  down the execution. A child left in OpenCode's process group dies with it, so
  an awaited `execFile` took a `SIGTERM` before it ever reached tmux. The plugin
  spawns the shim with `detached: true` and calls `unref()` so it survives in its
  own process group. Do not collapse that back into an awaited call.
- **The pane id goes stale.** A background `opencode2 serve --service` keeps the
  `TMUX_PANE` it first started in, which can be days old and cannot represent
  sessions in multiple panes. The plugin does not fire from that shared service.
  The shim still validates standalone pane ids against the live tmux server and
  records stale-pane skips even when debug is off.

Interactive `opencode2` launches default to `--standalone`, so the plugin shares
the pane you are sitting in. `oc` and the temporary `oc2` alias use that default.
`oc2bg` explicitly opts into the shared background service and gives up per-pane
notifications.

Restart OpenCode after editing the plugin.

### Focus gate

Before it flags a pane, the shim asks tmux, in the same call that checks for a
stale pane, whether a focused client is already looking at it. Every one of these
must hold:

- the pane is the active pane of its window;
- the window is the session's current window;
- the session's attached client has not reported focus-out. With several clients
  attached, any focused client counts;
- the server's `focus-events` option is on. Without it tmux never learns of a
  blur and treats every client as focused forever, which would hide the tint
  from someone who has switched to another app. `~/.tmux.conf` turns it on.

When they all hold, the shim skips the pane flag, the tint, and the window-tab
flag, and plays the group's sound. Which session needs you is left to OpenCode's
own tab indicators. A pane in a background split or another window, a client in
another app, and a detached session all keep the full tint.

The gate only removes visual output. A failed or unparsable lookup, or a tmux
too old to answer a field, falls back to the tint. It applies to all three
groups and only to `fire`; clearing is never gated. The Claude, Codex, and zsh
notifiers do not use it, and their behavior is unchanged.

One limit: tmux counts a client as focused from the moment it attaches until the
terminal reports a blur. A terminal that ignores tmux's focus request never
reports one, so the gate treats its active pane as watched. Ghostty reports
focus.

### Outside tmux

The shim and the plugin both stay silent when `$TMUX` or `$TMUX_PANE` is unset.
Sound there comes from OpenCode itself, so playing it from the bridge as well
would double-fire.

The `opencode2` wrapper turns on OpenCode's native `attention.sound` and gives it
the sounds from `notify.yaml`, by exporting a small `OPENCODE_CLI_CONFIG_CONTENT`.
It does this only for an interactive launch with `$TMUX` unset. The mapping is:

- `done` and `default` use `integrations.opencode.sound`;
- `subagent_done` is silent (`silence.mp3`), matching the tmux notifier, which
  ignores child sessions, so a DAG run does not chime once per sub-agent;
- `permission` and `error` use `integrations.opencode_permission.sound`;
- `question` uses `integrations.opencode_question.sound`.

Paths are absolute, under `~/.config/notify/sounds`, because OpenCode does not
expand `~`. OpenCode has one global volume, not one per event. It is the
`opencode` group's volume, else `settings.volume`, scaled from 0-100 to 0-1.
`attention.notifications` is never touched, so there are still no popups.

Native sound cannot be told to stay silent. A missing or empty path falls back to
a sound bundled with OpenCode. An empty `sound:` here therefore maps to
`sounds/silence.mp3`, a 0.2 s silent file shipped with the other sounds, and so
does a named file that does not exist, as the tmux notifier would stay quiet for
it. If `silence.mp3` itself is missing, the wrapper exports nothing.

The wrapper fails open and never overrides you. It exports nothing when `yq`, the
config, or the notify library is missing, and it leaves the variable alone when
`cli.override.json`, `override.zsh` or your own `OPENCODE_CLI_CONFIG_CONTENT`
already set it. `--version`, `--help` and the non-interactive subcommands skip the
lookup. It costs one `yq` call, about 70 ms, at launch.

### Own and elsewhere tints

The OpenCode TUI plugin draws its own indicators through four shim verbs. Like
every verb except `describe`, the tint verbs need `$TMUX` and `$TMUX_PANE` and skip
a stale pane. None of them plays a sound or applies the focus gate, because the
plugin decides when to call them.

- `tint own <group>` is the viewed tab's own alert: the group's full color on the
  pane and the window-tab pill, with `@notify` set. It leaves any stored
  elsewhere state alone.
- `tint elsewhere <group>` is a different tab needing attention. It stores a
  dimmed color and the accent in `@notify_elsewhere_bg` and
  `@notify_elsewhere_accent`. If the pane has no own tint it also shows the dimmed
  color and sets the pill. It never sets `@notify`. An own tint on screen wins.
- `tint clear` drops both kinds of state, restores the default pane color and
  clears the pill unless another pane in the window still needs it.
- `describe` prints one line of JSON and works with or without tmux: each OpenCode
  group's resolved `bg`, `accent`, `sound` and `volume`, the `elsewhere` `dim` and
  `base`, and an `elsewhereBg` per group. It prints `{}` when the config cannot
  be read.

Groups are `opencode` (turn done), `opencode_permission` (permission or error) and
`opencode_question`. The dimmed color is the group `bg` blended toward the palette
`background` by `settings.elsewhere_dim`, which defaults to 0.5. Zero is the full
group color and one is the background. A `bg` that is not `#rrggbb`, such as
`default`, passes through undimmed. The blend is integer shell arithmetic, so it
gives the same result in macOS `/bin/bash` 3.2, bash, dash and zsh.

The keypress and click bindings clear a pane only when `@notify` is set. That is
why an elsewhere tint, which never sets it, survives typing. When the own tint is
cleared, by a key, a click, or the `clear` verb, an elsewhere tint is put back as
the pane color and keeps the pill. Claude, Codex, and the zsh notifier never set an
elsewhere option, so their clearing behaves exactly as before.

The plugin owns these visuals. The server `notify.ts` keeps calling `fire` for
now, so the two can both color a pane until that is reconciled.

## Debugging

Debug logging is off by default. Set `settings.debug: true` in the YAML or
export `NOTIFY_DEBUG=1`.

Events are written to `settings.log`, which defaults to
`~/.config/notify/notify.log`. The log caps itself at roughly 1 MB. A
sound-only fire, whether outside tmux or gated by focus, logs a `sound-only`
line instead of a `fire pane=` line.

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
