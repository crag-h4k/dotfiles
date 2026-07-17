<!-- docs/notifications.md -->
# Notifications

## Table of Contents

- [Overview](#overview)
- [Standalone install (no chezmoi)](#standalone-install-no-chezmoi)

## Overview

Terminal-native attention cues when a long process finishes or Claude/Codex needs you. Visual
cue always; sound optional per group (empty sound = silent). No notification-center popups.

- **Config (one file):** everything - the color palette, per-group `bg`/`accent`/`sound`,
  default and per-group `volume`/`threshold`, the binary-to-group map, the ignore-list, and
  debug logging - lives in `~/.config/notify/notify.yaml`, read via
  [`yq`](https://github.com/mikefarah/yq) (mikefarah, v4). `groups` are triggered by a finished
  command's binary; `integrations` (claude/codex) are triggered by an event hook and are
  auto-added to the ignore-list (so launching the CLI never fires the command path). Palette
  names resolve to hex; a raw `#hex` or `default` passes through. Edit the YAML (new shells
  re-read it; `tmux source-file ~/.tmux.conf` reloads the renderer).
- **Shared logic:** `~/.config/notify/lib.sh` (array-free POSIX, sourced by both the zsh
  notifier and the bash hooks) reads the config and does the recolor + sound. It resolves a
  mikefarah `yq` even under a stripped PATH (preferring `~/.local/bin/yq`, ignoring a stray
  apt/kislyuk `yq`) and locates tmux the same way, bypassing the oh-my-zsh tmux wrapper.
- **Rendering:** `~/.tmux/conf.d/notify.conf` renders the status-bar flag (per-group accent) and
  pane tint, and clears them when you return focus to the pane. tmux is the only surface that
  draws; outside tmux the system is inert by design.
- **Detection:** `~/.zsh/custom/functions/notify-process.zsh` builds its binary-to-group map,
  per-group thresholds, and ignore-list once at shell init (a single `yq` call), then
  `preexec`/`precmd` flag the pane when a named binary (terraform, brew, ...) finishes at/above
  its group's threshold, or any command runs past the catch-all `default` threshold. A nonzero
  exit uses the `error` group.
- **AI attention:** the Claude Code `Stop`, `Notification`, and `PreToolUse:AskUserQuestion`
  events call `notify-tmux.sh`, registered in `~/.claude/settings.json` via the `modify_` template
  (`dot_claude/modify_settings.json.tmpl`) that merges the hooks on each `chezmoi apply` without
  clobbering model/effort/plugins. Matcher-less `Notification` covers permission prompts and
  idle; `PreToolUse:AskUserQuestion` covers the question tool (which emits no `Notification`
  event). `~/.claude/settings.local.json` is never loaded and `.claude` settings do not merge up
  the directory tree; the externally managed `~/.claude.json` is left untouched. A fresh `claude`
  session picks up the hooks. Codex is wired the same way via `~/.codex/config.toml` (the
  `modify_private_config.toml.tmpl` merge, gated on `ai > codex_hooks`): its external `notify` program
  calls `notify-tmux.sh` on `agent-turn-complete` (the color+sound "your turn" flag). Codex never
  sends the notify program an approval event, so `notify` cannot cover permission prompts; the
  merge also sets `tui.notifications` (`approval-requested`), Codex's own alert, which is a no-op
  under tmux today ([openai/codex#16855](https://github.com/openai/codex/issues/16855)) and
  activates once that lands. A restart of `codex` picks up the config.
- **Debug:** off by default. Set `settings.debug: true` (or `export NOTIFY_DEBUG=1`) to trace
  fires to `settings.log` (default `~/.config/notify/notify.log`); the log self-caps at ~1 MB.
- **yq dependency:** installed with the `zsh` or `tmux` component: `brew install yq` on macOS,
  the mikefarah binary fetched to `~/.local/bin` on Debian. Do **not** `apt install yq` on
  Debian - that is a different (python/kislyuk) tool with incompatible syntax, which the system
  detects and ignores.

### Standalone install (no chezmoi)

To install only the notify subsystem on a machine that does not use the full chezmoi dotfiles,
run the standalone installer from a checkout of this repo:

```sh
scripts/install-notify.sh          # --force to overwrite an existing notify.yaml
```

It copies the same files into `~/.config/notify/` (including `sounds/`), `~/.tmux/conf.d/`, and
`~/.claude/hooks/`, installs mikefarah `yq` (brew on macOS, binary to `~/.local/bin` on Debian),
and wires `~/.zshrc`, `~/.tmux.conf`, and `~/.claude/settings.json`. When the `codex` CLI is
present it also installs `~/.codex/hooks/notify-tmux.sh` and merges `notify` + `tui.notifications`
into `~/.codex/config.toml` (mode 600 preserved). It is idempotent. If you use `chezmoi apply`,
notify is already installed - do **not** also run this (the zsh notifier would load twice); the
script refuses unless you pass `--force`. This is the same layout `chezmoi apply`
installs.

Manual equivalent, if you prefer not to run the script:

1. `mkdir -p ~/.config/notify/sounds ~/.tmux/conf.d ~/.claude/hooks`
2. Copy `dot_config/notify/notify.yaml`, `dot_config/notify/lib.sh`, and
   `dot_config/notify/sounds/*.mp3` to `~/.config/notify/` (sounds go in
   `~/.config/notify/sounds/`); `dot_zsh/custom/functions/notify-process.zsh` to
   `~/.config/notify/notify-process.zsh`; `dot_tmux/conf.d/notify.conf` to `~/.tmux/conf.d/`; and
   `dot_claude/hooks/executable_notify-tmux.sh` / `executable_notify-clear.sh` to
   `~/.claude/hooks/notify-tmux.sh` / `notify-clear.sh` (then `chmod +x` both).
3. Install mikefarah `yq`: `brew install yq` (macOS) or fetch the `yq_linux_<arch>` binary to
   `~/.local/bin` (Debian; do **not** `apt install yq` - that is a different tool).
4. Add to `~/.zshrc`: `[ -f ~/.config/notify/notify-process.zsh ] && source ~/.config/notify/notify-process.zsh`
5. Add to `~/.tmux.conf`: `source-file ~/.tmux/conf.d/notify.conf` (this overrides
   `window-status-format` / `pane-border-format` - reconcile with your status bar).
6. Register the Claude hooks. The merger is now a chezmoi template
   (`dot_claude/modify_settings.json.tmpl`), so render it with the hooks gate on before running
   it. Easiest is to let `scripts/install-notify.sh` do this step (it renders the template for the
   notify path and merges it, preserving your existing settings). To do it by hand with chezmoi
   available: `printf '[data.components.ai]\n    claude_hooks = true\n' > /tmp/g.toml && chezmoi
   execute-template --config /tmp/g.toml < dot_claude/modify_settings.json.tmpl > /tmp/m.py && python3
   /tmp/m.py < ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json`.
7. Reload: `tmux source-file ~/.tmux.conf`, open a new shell, restart Claude Code.
