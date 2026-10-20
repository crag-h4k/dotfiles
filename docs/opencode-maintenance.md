<!-- docs/opencode-maintenance.md -->
# OpenCode2 integration maintenance

## Table of Contents

- [Maintenance rules](#maintenance-rules)

## Maintenance rules

Read the repo's `docs/operation.md`, `docs/notifications.md`, and
`docs/agent-skills.md`. This integration targets OpenCode V2. Check the actual
CLI, server, plugin SDK, and terminal versions when diagnosing compatibility.

- The wrapper owns the isolated CLI entrypoint. An attached client can use a
  different server and filesystem; establish that boundary before claiming the
  repository is missing or changing another checkout.
- Keep generic configuration in source and preserve unmanaged `cli.override.json`,
  `override.zsh`, `remote.env`, and `v2-plugins/local`. Private permissions, provider
  connections, notification bridges, and server routing belong in the overlays.
  The narrow Plan handoff-root permissions are portable managed exceptions;
  host-specific handoff roots still need private rules.
- Preserve merge-managed JSONC and unknown user settings. Inspect the renderer
  for the active V2 schema; older OpenCode flags and plugin APIs are not a basis
  for a fix. Do not silently alter account, model, or permission selection.
  The managed shell policy allows both `prek *` and `pre-commit *` for local
  checks; it does not replace host-specific permissions.
- `cli.json` is merge-managed by `modify_private_cli.json.tmpl` because V2's
  **Open settings** writes it. Keep the enforced set small: only keys that
  protect a dotfiles integration (`attention.*` so tmux stays the single alert
  channel, the leader and the tab navigation keys with the pane and terminal
  defaults they replace, the managed `plugins`). Seed every other default per leaf
  and never overwrite it. Check the live schema at `opencode.ai/v2/cli.json`
  before adding a key, because the TUI rejects unknown settings, and keep
  `tabs.enabled` and `tabs.mode` from coexisting. Inline `cli.override.json`
  replaces arrays rather than merging them; do not move the managed `plugins`
  there. Extend `tests/test_merge_opencode_cli.py` with any ownership change.
- The marked global permissions allow edit tools below `~/.agents/` and
  `~/.claude/` so OC2 can maintain shared skills and Claude state. Keep that
  scope deliberate: generic secret suffixes, cloud and SSH paths, and
  `~/.claude.json` remain denied. Recursive shell deletion remains denied even
  inside these roots.
- The server plugin merge owns marked registrations, not the whole array.
  Preserve local entries and ordered controls after `dotfiles:plugins:end`, and
  preserve managed object options when changing a pin. Keep conflicts and
  malformed input on the warning-and-passthrough path; do not silently choose
  between competing versions. CLI-only plugin overrides remain separate.
- Stage and check CLI/plugin runtime compatibility and required imports before
  switching the stable binary or runtime links. Preserve old releases on failure.
  Chezmoi must not manage runtime node_modules, npm lockfiles, or authentication.
  Resolve OpenTUI and Solid.js against the selected SDK's declared peers through
  `npm-candidate.sh`. Chezmoi-driven npm work, including the wrapper and runtime
  sync, runs with `NPM_CONFIG_MIN_RELEASE_AGE=0` in its process environment only.
  Do not add per-package aging exceptions or write the user's npm config. Metadata
  failure must not start installation.
- The footer is the `opencode-pillbox-statusline` package. Dotfiles owns its
  `@latest` reference in both config files, the `opencode.jsonc` reference audit, and the
  seeded `cli.json` color options; pill behavior, quota sources, and their
  tests belong upstream. Review a new release before an explicit plugin update; keep
  Copilot tiers opt-in. Keep color overrides as theme tokens with a fallback,
  not palette hex values; `tests/test_opencode_theme.py` proves the hues.
  Retire a removed managed entry through `RETIRED_PLUGINS` in the `cli.json`
  merge and its files through `home/.chezmoiremove`.
- Sidequest uses the same `@latest` reference in both config files so terminal options reach its
  single TUI instance. Seed its `focusKey` option to `<leader>p`; the leader stays
  on OpenCode's default `ctrl+x`. Plugin command IDs are not valid `cli.json.keybinds` keys.
  Free the stock sidebar toggle for `<leader>b` while preserving custom bindings
  and private plugin options. The panel implementation and its tests belong in
  the Sidequest repository. Keep Pillbox's Sidequest pill disabled until its
  adapter consumes the producer's actual metadata fields.
- Diagnose glyph widths, capability probes, RGB backgrounds, and tmux differences
  in the actual terminal chain. The project supports Ghostty over SSH and tmux,
  and has regression history with Termius. Changing the font alone is insufficient
  evidence. Pillbox's `nerd-bmp` icon set avoids glyphs above U+FFFF.
- Preserve the inexpensive `/demo` path in `v2-plugins/demo`. A showcase should
  not require extra model calls or filesystem changes. Maintenance command
  routers are prompt-only, treat arguments as task data, and grant no additional
  tool permissions.
- The terminal session-workflow plugin switches the current session among
  Build, Plan, and Auto. It does not reorder native tabs. Auto is a primary
  agent; the terminal plugin replies once to its permission asks while
  connected, never to question forms. Configured denials create no request.
  That handler also owns Auto approval-failure notifications. Do not infer a
  failed approval from a timer in a second event subscriber.
  Keep the native agent picker available if the plugin fails to load.
  Before the first prompt creates a session, Shift+Tab falls through to the
  native home-screen agent cycle. Do not create or query a session merely to
  select the initial mode, and return `false` synchronously for that key path.
- The agent-catalog CLI plugin reads OpenCode's agent registry for the current
  location. Open it through the command palette as **Browse configured agents**
  or run `/subagents` or `/subagents-catalog`. It is read-only: browsing an agent
  never switches the session agent or launches a child session. Keep it on the
  registry API rather than parsing `agents/` files so project overrides, hidden
  profiles, and configuration merges stay accurate.

OpenCode's footer ships with its OpenCode selection; inspect the active gates
before assuming the separate Claude/Codex statusline feature enables it.
Shared skills use per-entry compatibility links. Keep their normal discovery
and selection working alongside private and independently installed skills.
