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
yamllint, and Luacheck. They remain available in a shell and can be reused by
CI or other editors. Mason owns TFLint for Neovim.

On macOS, Homebrew installs `markdownlint-cli2`. On Debian, it is installed
user-globally through npm under `~/.local`. `nvim-lint` uses that same binary;
Mason does not install a duplicate.

`prettierd` has no Homebrew formula, so the Neovim installer installs it through
npm under `~/.local` on both platforms. `conform.nvim` shells out to that
binary; Mason does not install a duplicate.

Luacheck is installed and inventoried in the explicit LuaRocks tree
`$HOME/.luarocks`, with its executable linked into `~/.local/bin`. This also
works for root, where LuaRocks rejects `--local`. macOS uses Lua 5.4 for
Luacheck compatibility.

The Python provider is transactional. A sibling venv receives the floating
`pynvim` package and must import it before the stable
`~/.local/share/nvim-venv` symlink changes. A working previous venv remains in
the release directory, and a partial or corrupt legacy venv is repairable.

On Debian, the upstream Neovim archive is checksum-verified and extracted as a
complete versioned tree. The binary, runtime, and libraries pass a headless
health check before one stable pointer and wrapper switch. No files are overlaid
into the live runtime, and the previous tree remains available for rollback.
Each health check has a ten-second deadline. Re-running the installer repairs
the launcher even when the installed release is already current.

If an older installer stops after the archive download reaches 100%, its
generated launcher may be passing a literal `$@` instead of forwarding the
health-check arguments. Use the corrected installer to rebuild the launcher;
deleting the downloaded release is unnecessary.

nvim-treesitter's `main` branch builds parsers with the `tree-sitter` CLI, which
is a separate package from the C library. On macOS, Homebrew split them: the
`tree-sitter` formula ships only `libtree-sitter`, and the CLI lives in
`tree-sitter-cli` (installs the `tree-sitter` binary). The package plan installs
both. On Debian there is no separate library package: Neovim's bundled runtime
loads the parsers, and only the CLI is installed, from a github-release binary
under `~/.local`. Parser compilation uses the system C compiler (`cc`): the
Apple Command Line Tools on macOS, `build-essential` on Debian. A fresh macOS
host without the Command Line Tools fails an early preflight that points at
`xcode-select --install`. Without the CLI, parser builds fail and
`~/.local/share/nvim/site/parser` stays empty, so startup keeps retrying the
install. If a rebuilt machine hits that, confirm `tree-sitter --version` resolves
before debugging further.

Parser install is diffed against what is already present: `init.lua` installs
only the parsers missing from the install dir, rather than the whole set on every
launch. Package mode previews each configured or installed parser against the
manifest in the candidate Treesitter plugin revision, then installs only the
approved changes. `:TSUpdate` performs a manual refresh inside Neovim.

Mason owns editor-only Gitleaks and the language servers. Startup installs only
missing packages. The package plan refreshes registry metadata and shows the
installed and candidate version of each configured or installed package.
Approval selects those versions for that run without imposing one exact
version across hosts.

## Terminal display

The shared palette defines RGB highlight colors. The configuration explicitly
enables `termguicolors`, so terminals advertised as `xterm-256color` still render
those syntax colors.

On Linux, `termfeatures.osc52 = false` disables automatic OSC52 capability
detection. This suppresses the clipboard query that can appear as `+q4D73` in
Termius. Tmux, X11, Wayland, and explicitly configured clipboard providers remain
available. See the [upstream terminal report](https://github.com/neovim/neovim/issues/39661)
and [Neovim's clipboard detection setting](https://neovim.io/doc/user/provider/#g:termfeatures).

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

Lazy bootstraps itself under Neovim's data directory. The package plan lists each
plugin's installed and candidate commit; unchanged plugins are skipped, and
installation uses the approved commits. Discovery reads the shared plugin
specifications without running startup callbacks or installing plugins. The
declarative plugin list stays in the repo, while downloaded state stays on the
host.

`lazy-lock.json` is ignored intentionally. Normal Lazy or Mason updates should
not dirty the dotfiles checkout, and this repo does not promise exact
cross-host runtime revision reconciliation.

Use `cup` for the complete package-mode update, or these commands for an
editor-only manual update:

```vim
:Lazy sync
:Mason
```

Review changes in the actual plugin or tool before rolling them onto every
host. “It updated itself” is not a release strategy.

## Linters and diagnostics

`nvim-lint` consumes the shell-visible tools installed by the package plan.
Diagnostics are editor feedback; repository enforcement still belongs to
prek and project CI.

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
