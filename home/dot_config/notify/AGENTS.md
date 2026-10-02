# Terminal notifier

Read `docs/notifications.md` and `docs/sounds.md` from the repo root. This is a
shared subsystem used by process detection, tmux, and AI attention hooks.

- Behavior lives in notify.yaml; palette colors come from the shared catalog.
  Preserve named semantic colors, raw hex/default support, group thresholds,
  volume controls, and an empty sound as silent. Avoid consumer-specific copies.
- Keep the library array-free POSIX shell. Zsh command detection stays in the
  Zsh hook. Locate the real tmux binary under a stripped PATH, bypassing the
  Oh My Zsh wrapper, and require the compatible mikefarah yq implementation.
- Visual attention is always present in tmux; sound is configurable. Outside
  tmux the managed notifier deliberately does nothing. Preserve terminal-native
  behavior without adding notification-center popups or another network service.
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
the affected tmux input bindings. Use a separate tmux server/socket. Never kill
a live server or install packages to run an ordinary notifier test.
