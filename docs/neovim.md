<!-- docs/neovim.md -->
# Neovim

Neovim gets a curated editor stack without pretending every machine must run
the same plugin byte forever. Chezmoi owns the declarations; Lazy and Mason
build the local runtime.

## Ownership

| Owner | What it controls |
| --- | --- |
| Chezmoi | `~/.config/nvim`, LSP declarations, plugin declarations, linter wiring, and the selected palette |
| Package installer | Shell-visible tools useful outside Neovim |
| Mason | Neovim-specific executables and the desired LSP server set |
| Lazy | Neovim plugins installed on this machine |

The package installer owns `markdownlint-cli2`, `prettierd`, ShellCheck,
yamllint, TFLint, Trivy, and Luacheck. They remain available in a shell and can
be reused by CI or other editors.

On macOS, Homebrew installs `markdownlint-cli2`. On Debian, it is installed
user-globally through npm under `~/.local`. `nvim-lint` uses that same binary;
Mason does not install a duplicate.

`prettierd` has no Homebrew formula, so the Neovim installer installs it through
npm under `~/.local` on both platforms. `conform.nvim` shells out to that
binary; Mason does not install a duplicate.

nvim-treesitter's `main` branch builds parsers with the `tree-sitter` CLI, which
is a separate package from the C library. On macOS, Homebrew split them: the
`tree-sitter` formula ships only `libtree-sitter`, and the CLI lives in
`tree-sitter-cli` (installs the `tree-sitter` binary). The package plan installs
both. On Debian, the library comes from apt and the CLI from a github-release
binary under `~/.local`. Without the CLI, parser builds fail and
`~/.local/share/nvim/site/parser` stays empty, so startup keeps retrying the
install. If a rebuilt machine hits that, confirm `tree-sitter --version` resolves
before debugging further.

Parser install is diffed against what is already present: `init.lua` installs
only the parsers missing from the install dir, rather than the whole set on every
launch. Run `:TSUpdate` to refresh installed parsers.

Mason owns editor-only Gitleaks and the language servers. It installs packages
only when missing. Startup does not update an installed package or reconcile
exact versions between hosts.

## LSP activation

The desired server set is declared once in `init.lua`:

- Bash
- Docker's official Dockerfile and Compose server
- GitHub Actions
- Jinja
- JSON
- Lua
- Markdown
- Pyright
- Terraform
- TFLint
- YAML

`mason-lspconfig` maps those Neovim server IDs to Mason packages and installs
missing servers. Neovim then activates them through `vim.lsp.config()` and
`vim.lsp.enable()`.

There is no parallel `lspconfig.SERVER.setup()` path waiting to drift out of
sync.

Useful checks:

```vim
:checkhealth
:LspInfo
:Mason
```

## Plugins and local revision state

Lazy bootstraps itself under Neovim's data directory and syncs plugins during
the Neovim installer. The declarative plugin list stays in the repo, while
downloaded plugin state stays on the host.

`lazy-lock.json` is ignored intentionally. Normal Lazy or Mason updates should
not dirty the dotfiles checkout, and this repo does not promise exact
cross-host runtime revision reconciliation.

Use these commands when you want to update a machine:

```vim
:Lazy sync
:Mason
```

Review changes in the actual plugin or tool before rolling them onto every
host. “It updated itself” is not a release strategy.

## Linters and diagnostics

`nvim-lint` consumes the shell-visible tools installed by the package plan.
Diagnostics are editor feedback; repository enforcement still belongs to
pre-commit and project CI.

Gitleaks is the exception on the executable side because its read/save scans
exist only for Neovim. See [Gitleaks](gitleaks.md) for exclusions, project
allowlists, and why warnings never block a save.

## Formatting

`conform.nvim` runs `prettierd` against `json`, `jsonc`, and `yaml` buffers.
Other languages keep their own tooling, and markdown is left to markdownlint so
Prettier does not fight the linter's rules.

Formatting is manual, never on save. `<leader>f` (space, then `f`) formats the
buffer in normal mode, or the selection in visual mode.

## CodeCompanion

CodeCompanion is opt-in under `ai > codecompanion`. It loads only when
`~/.config/nvim/.codecompanion-enabled` exists, because sending a buffer to an
LLM should require a deliberate yes on each host.

The Claude ACP bridge installs under `~/.local/bin` and reuses the existing
Claude login. No extra API token is written into the repository.

Toggle the host-local sentinel directly:

```sh
touch ~/.config/nvim/.codecompanion-enabled
rm ~/.config/nvim/.codecompanion-enabled
```

Restart Neovim after changing it.
