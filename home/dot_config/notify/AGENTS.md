# Terminal notifier

Read `docs/notifications.md` and `docs/sounds.md` from the repo root. This is a
shared subsystem used by process detection, tmux, and AI attention hooks.

- Behavior lives in notify.yaml; palette colors come from the shared catalog.
  Preserve named semantic colors, raw hex/default support, group thresholds,
  volume controls, and an empty sound as silent. Avoid consumer-specific copies.
- Keep the library array-free POSIX shell. Zsh command detection stays in the
  Zsh hook. Locate the real tmux binary under a stripped PATH, bypassing the
  Oh My Zsh wrapper, and require the compatible mikefarah yq implementation.
- Visual attention is present in tmux; sound is configurable. Outside tmux the
  process notifier, the Claude and Codex hooks, and the OpenCode bridge
  deliberately do nothing. The one outside-tmux sound is OpenCode's own
  `attention.sound`, which the `opencode2` wrapper builds from notify.yaml
  (`notify_attention_config` in the library). It never turns on
  `attention.notifications`, so there are still no popups, and the bridge must
  stay silent there or both would fire. Native sound has no way to say "none": a
  missing or empty path falls back to a bundled sound, so an empty `sound:` maps
  to `sounds/silence.mp3`. Keep that file.
- Inside tmux the OpenCode shim's `fire` withholds the visual flag only when tmux
  positively reports a focused client on the pane's active pane and current
  window, with `focus-events` on; the sound still plays, and any doubt keeps the
  tint. Claude, Codex, and zsh never use that gate. Preserve terminal-native
  behavior without adding notification-center popups or another network service.
- The OpenCode TUI plugin drives visuals through shim verbs: `tint own`,
  `tint elsewhere`, `tint clear` and `describe`. The plugin owns those visuals;
  the server `notify.ts` keeps calling `fire` until that changes. An elsewhere
  tint (another tab needs attention) lives in `@notify_elsewhere_bg` and
  `@notify_elsewhere_accent` and never sets `@notify`, because the keypress
  binding clears a pane only when `@notify` is set. An own tint supersedes it, and
  `notify_clear` clears only the own tint and puts the elsewhere one back. Claude,
  Codex, and zsh never set either option, so their clear is unchanged. Do not
  make a verb play sound or apply the focus gate: the plugin decides.
- AI binaries belong to their integration hooks and are excluded from process
  detection. Permission/questions, completion, and user input must keep their
  intended event semantics across Claude, Codex, and OpenCode.
- Clear flagged panes on the existing focus, keyboard, click, drag, and scroll
  paths. Preserve right-click menus, drag-to-copy, and wheel scrolling through
  Ghostty over SSH into tmux. Do not disable bindings to mask a regression.
- Keep a single owner for each indicator and notification event. Preserve
  statusline integration and source order; avoid competing writes to the same
  tmux option or duplicate sounds from multiple bridges.

Test event mapping, stripped PATH lookup, silent groups, process outcomes, and
the affected tmux input bindings. For the focus gate, cover the fail-open table
with a tmux stub and cover real client focus with a pty-attached client on a
separate socket (`tests/tmux_client.py`, which can also type a key to exercise
the real clear binding). Test the hex blend in every installed shell, including
macOS `/bin/bash` 3.2 and dash. Use a separate tmux server/socket. Never kill a
live server or install packages to run an ordinary notifier test.
