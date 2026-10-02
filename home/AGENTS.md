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
  AI sub-feature gate without a new menu item. Use one canonical store and one
  link per skill in each compatibility root; preserve independently added skills.
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
  credentials, and OpenCode permissions or routing belong in those private files.
- Keep Lazy's lockfile, downloaded plugins, OpenCode runtime links and npm state,
  caches, transcripts, and authentication unmanaged. Chezmoi declares desired
  configuration; application/package managers own their local runtime state.
- `AGENTS.md` files in this tree are repository guidance. Keep both the root and
  recursive ignore patterns so no such file becomes target-home instructions.

## Rendering

Use the committed palette catalog as the source of semantic colors. Palette
generation is an authoring operation; init/apply must work from the committed
catalog without fetching its submodule. Preserve saved choices on re-init.

Use disposable config, source, destination, and state paths for render tests.
Check positive and negative component selections and cross-platform output.
Follow the deeper OpenCode, Neovim, or notifier guidance for those consumers.
