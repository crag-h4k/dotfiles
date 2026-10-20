# Managed source

`home/` is the chezmoi source root. Repository scripts, tests, docs, CI, and
authoring inputs live outside it. Read `docs/architecture.md` and
`docs/components.md` from the repository root when changing the component model.

## Selection and ownership

- Chezmoi owns selection through `.chezmoi.toml.tmpl`, `[data.components]`,
  `.chezmoiignore`, and `.chezmoiexternal.toml`. Preserve nested `git`, `ai`, and
  `terminal` tables. Do not make an installer drive `chezmoi apply`.
- A component change must reach its menu/defaults, file and external gates,
  installation flags, package records, render matrix, and docs as applicable.
  An unselected component must not fetch its externals.
- AI tools remain under the opt-in AI parent. Shared skills follow the existing
  AI sub-feature gate without a new menu item. Use one canonical store, per-skill
  links under `~/.agents/skills`, and the managed `~/.claude/skills` compatibility
  link. Preserve independently added skills during its explicit migration.
- Keep OS-specific behavior gated by both selection and OS. iTerm2 remains an
  opt-in macOS terminal feature. Use declarative profiles and a small explicit
  preference list instead of importing whole application state.

## Preserve local state

- Edit source configuration and inspect its rendered diff. Before overwriting a
  target changed since the last apply, determine whether it belongs in source or
  an unmanaged override. Do not choose `all-overwrite` for an unexplained diff.
- `modify_` files are merge programs even when their target extension is JSON or
  TOML. Preserve unrelated keys, comments where supported, private permissions,
  and the host's model, project, and plugin settings. Validate the rendered merge.
- `docs/operation.md` defines optional local override paths and load order.
  Preserve those files and their ignore entries. Personal Git identities,
  credentials, host-specific OpenCode permissions, and routing belong in those
  private files. Plan's portable handoff-root permissions are managed source.
- `worktreesDir` and `agentsDir` are data keys whose saved values win on re-init;
  the `DOTFILES_WORKTREES_DIR` and `DOTFILES_AGENTS_DIR` env vars only seed a first
  init. Resolve them through `.chezmoitemplates/dotfiles-dir` with `dig` defaults so
  old configs keep rendering. Init asks for both at the end of the AI submenu,
  pre-filled (saved, then env seed, then default); `DOTFILES_NO_TUI`, no usable
  terminal, `cup`, and an unselected AI component skip the prompt, and `apply` never
  prompts. Apply creates the directories but never runs sudo; it prints the
  privileged command instead. Existing worktrees and notes are not moved. Plan's
  handoff permissions follow `agentsDir` through the same template.
- Keep Lazy's lockfile, downloaded plugins, OpenCode runtime links and npm state,
  caches, transcripts, and authentication unmanaged. Chezmoi declares desired
  configuration; application/package managers own their local runtime state.
- `AGENTS.md` files in this tree are repository guidance. The one exception is
  `modify_private_AGENTS.md.tmpl` for OpenCode's global instructions; preserve local content
  and gate it on `ai > opencode`. Keep other guidance excluded from target homes.

## Rendering

Use the committed palette catalog as the source of semantic colors. Palette
generation is an authoring operation; init/apply must work from the committed
catalog without fetching its submodule. Preserve saved choices on re-init.

Use disposable config, source, destination, and state paths for render tests.
Check positive and negative component selections and cross-platform output.
Follow the deeper OpenCode, Neovim, or notifier guidance for those consumers.
