# Neovim configuration

Read `docs/neovim.md` from the repo root and inspect the active plugin APIs before
changing the configuration. Preserve the tool ownership split:

| Owner | Responsibility |
| --- | --- |
| Chezmoi | Configuration, desired plugins/LSPs, linter wiring, shared palette |
| Package installer | General-purpose executables usable from the shell |
| Mason | Desired language servers and editor-only executables |
| Lazy | Local Neovim plugins |

- Startup provisions missing packages/parsers. Routine version changes belong
  in the approved package run. Preview individual Lazy, Mason, and Treesitter
  candidates and apply the approved versions/revisions.
- Keep lazy-lock.json and package/revision state local. Preserve the optional
  unmanaged `lua/override.lua` and its documented load order.
- Avoid duplicate tool ownership. Shell-visible markdownlint-cli2, prettierd,
  ShellCheck, yamllint, and Luacheck belong to the package installer. Mason owns
  TFLint and Gitleaks with the configured language servers.
- Verify the installed Treesitter branch/API, parser manifest, compiler, and CLI.
  The tree-sitter C library alone does not supply the CLI. Check actual plugin
  names and activation before diagnosing a headless loader failure.
- Use current Neovim LSP activation and real server names. Scope specialized
  language servers to their intended files instead of every buffer of that type.
- Keep Gitleaks warnings asynchronous and redacted, respecting project allowlists.
  Expensive scans and package updates must not block ordinary editor startup.
- Preserve complete binary/runtime/library trees and health checks during
  installation. Repair a launcher or provider transaction without deleting the
  previous working release or changing source ownership.
- Preserve truecolor and shared palette highlights. Reproduce display issues
  through the actual Ghostty/SSH/tmux or Termius chain; capability-query response
  text and missing syntax colors need terminal and parser checks.

Validate syntax, rendered palette consumers, targeted editor/package tests, and
headless startup as appropriate. Use an isolated home/data directory for tests;
do not update the current user's plugins as a verification step.
