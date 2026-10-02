# OpenCode2 integration

Read the repo's `docs/operation.md`, `docs/notifications.md`, and
`docs/agent-skills.md`. This integration targets OpenCode V2. Check the actual
CLI, server, plugin SDK, and terminal versions when diagnosing compatibility.

- The wrapper owns the isolated CLI entrypoint. An attached client can use a
  different server and filesystem; establish that boundary before claiming the
  repository is missing or changing another checkout.
- Keep generic configuration in source and preserve unmanaged `cli.override.json`,
  `override.zsh`, `remote.env`, and `v2-plugins/local`. Private permissions, provider
  connections, notification bridges, and server routing belong in the overlays.
- Preserve merge-managed JSONC and unknown user settings. Inspect the renderer
  for the active V2 schema; older OpenCode flags and plugin APIs are not a basis
  for a fix. Do not silently alter account, model, or permission selection.
- Stage and check CLI/plugin runtime compatibility and required imports before
  switching the stable binary or runtime links. Preserve old releases on failure.
  Chezmoi must not manage runtime node_modules, npm lockfiles, or authentication.
- Keep the managed footer on the shared palette and native V2 rendering API.
  Provider usage belongs at the far right. Preserve monthly Copilot and weekly
  quota coverage for direct logins and compatible gateways when available.
  Distinguish unavailable quota data from a measured zero; keep refreshes off the
  render path and do not expose credentials in diagnostics.
- Diagnose glyph widths, capability probes, RGB backgrounds, and tmux differences
  in the actual terminal chain. The project supports Ghostty over SSH and tmux,
  and has regression history with Termius. Changing the font alone is insufficient
  evidence. Use the existing demo diagnostics and automated footer tests.
- Preserve the inexpensive `/demo` path. A showcase should not require extra
  model calls or filesystem changes. Maintenance command routers are prompt-only,
  treat arguments as task data, and grant no additional tool permissions.

OpenCode's footer ships with its OpenCode selection; inspect the active gates
before assuming the separate Claude/Codex statusline feature enables it.
Shared skills use per-entry compatibility links. Keep their normal discovery
and selection working alongside private and independently installed skills.
