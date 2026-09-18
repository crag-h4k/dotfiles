<!-- docs/components.md -->
# Components

## Table of Contents

- [Choosing components](#choosing-components)
  - [Palette and install confirmation](#palette-and-install-confirmation)
  - [Adding APT repositories](#adding-apt-repositories)
  - [Sub-feature submenus (git, ai, terminal)](#sub-feature-submenus-git-ai-terminal)
  - [OpenCode V2 footer](#opencode-v2-footer)
  - [Terminal (Ghostty, iTerm2)](#terminal-ghostty-iterm2)
    - [Ghostty](#ghostty)
    - [iTerm2](#iterm2)
- [Changing components later](#changing-components-later)
  - [Updating packages](#updating-packages)
  - [Changing the palette](#changing-the-palette)
  - [Changing the Zsh prompt](#changing-the-zsh-prompt)

## Choosing components

With [`gum`](https://github.com/charmbracelet/gum) installed, `chezmoi init`
opens a checkbox picker. Space toggles a component, Enter confirms, and Escape
cancels.

On later runs, the picker preselects the current host configuration. The header
also lists what is enabled. Gum is part of both platform base sets, so it is
available after the first package-mode apply.

The persisted `[data.components.*]` values also preserve selections originally
made through `all` or `all+`.

Without Gum, the same choices appear as a numbered prompt:

```text
Components to install:
  1) zsh          oh-my-zsh, plugins, custom functions, aliases
  2) tmux         tmux + plugins (tpm, resurrect, sensible, yank)
  3) neovim       neovim, lazy.nvim, language servers, linters
  4) git          git config files (config, personal, ignore_global)
  5) ai           AI tools (claude_hooks, codex_hooks, statusline, opencode, copilot, codecompanion, opencode2)
  6) terminal     terminal emulator config (ghostty, iterm2)
  7) colorscheme  re-pick the shared color scheme (unchecked keeps the current one)
  8) install_mode re-choose packages vs configs (unchecked keeps the current one)

  all   the default set (1 2 3 4)
  all+  everything, adds ai, terminal, colorscheme, install_mode

Enter numbers (e.g. "1 3"), a keyword above, or press Enter for default (1 2 3 4)
```

Both interfaces produce the same `componentSelection` value and
`[data.components]` tables.

| Input | Selects |
| --- | --- |
| Numbers (e.g. `1 3`) | Any subset; spacing/order don't matter - `1 3`, `13`, and `3 1` are equivalent |
| Enter | The default, `1 2 3 4` (zsh + tmux + neovim + git; no AI tools) |
| `all` | The default set (`1 2 3 4`) |
| `all+` | Everything, adding the AI tools, `terminal`, and the `colorscheme` / `install_mode` toggles |

`all+` uses each parent's default sub-features. For example, it enables Ghostty
but not iTerm2. Select iTerm2 in the terminal submenu when you want both.

The component list in `home/.chezmoi.toml.tmpl` is the source of truth for both
interfaces. Set `DOTFILES_NO_TUI=1` to force the numbered prompt.

`colorscheme` and `install_mode` are init-time actions. They live outside
`[data.components]` and reopen the relevant picker when selected.

### Sub-feature submenus (git, ai, terminal)

`git`, `ai`, and `terminal` open a second picker for sub-features. Their values
live in nested tables such as `[data.components.git]`; the parent is considered
on when any child is true.

Git is in the default component set. AI and terminal configuration are opt-in.

| Component | Sub-feature | Target | Submenu default | Notes |
| --- | --- | --- | --- | --- |
| `git` | `config` | `~/.gitconfig` | off | chezmoi-managed shared Git behavior and GitHub CLI credential helpers |
| `git` | `personal` | `~/.gitconfig.personal` | off | chezmoi prompts once for per-host name/email and renders the file privately (mode 600) |
| `git` | `ignore_global` | `~/.gitignore_global` | on | matches the old, pre-submenu default behavior |
| `ai` | `claude_hooks` | `~/.claude/settings.json` (merge) | off | merges the Claude notify hooks |
| `ai` | `codex_hooks` | `~/.codex/config.toml` (merge) | off | merges the Codex notify hook + `tui.notifications` |
| `ai` | `statusline` | `~/.claude/settings.json` + `~/.codex/config.toml` (merge) | off | Claude renderer plus a matching selected-palette Codex theme; keeps those files managed even when notify hooks are off; not enabled by `all` or `all+` |
| `ai` | `opencode` | OpenCode CLI (`opencode-ai` npm) + generic config (merge) + tmux notifier bridge | off | pinned npm binary into `~/.local`; `~/.config/opencode/opencode.jsonc` is merge-managed - chezmoi asserts `$schema`, V1 `plugin`, and V2 `plugins`; seeds `permission` only on a host that has none; and preserves every other top-level key (`instructions`, `mcp`) and its comments verbatim, so machine-local entries never reach this repo; not enabled by `all` or `all+` |
| `ai` | `copilot` | GitHub Copilot CLI (`@github/copilot` npm, `prerelease` tag) | off | npm-only channel (no Homebrew/apt); binary into `~/.local`; needs Node 22+; not enabled by `all` or `all+` |
| `ai` | `codecompanion` | CodeCompanion.nvim + `claude-agent-acp` bridge | on (within the `ai` submenu, if `ai` is picked) | heaviest sub-feature - pulls in node, npm, and the npm-installed bridge; listed near the end for that reason |
| `ai` | `opencode2` | OpenCode v2 CLI (`@opencode/cli` npm, stable `latest` tag) + shared generic config (merge) + `gud-lucent` theme | off | package isolated under `~/.local/share/opencode2` with only `opencode2` linked into `~/.local/bin`, so its additional `opencode` bin cannot overwrite V1; exact local-plugin dependencies install under `~/.config/opencode/node_modules`; V2 loads the pinned Copilot quota RPC while V1 keeps its separate legacy plugin list; not enabled by `all` or `all+` |
| `terminal` | `ghostty` | Ghostty config + quick-terminal dropdown | on | macOS and Linux |
| `terminal` | `iterm2` | iTerm2 Dynamic Profiles | off | macOS only; hidden in the submenu on non-macOS (data key still emitted for column parity), also gated in `home/.chezmoiignore` |

Gum preselects the parent's current sub-features on a re-init. A new parent uses
its documented defaults. The typed submenu behaves the same way, with Enter
accepting the defaults.

Sub-feature descriptions use `/` instead of commas in the Gum option string.
Gum treats commas as selection separators, which otherwise breaks preselection.
The submenu only appears when its parent is selected.

Nothing AI-related installs unless the AI component is selected.

CodeCompanion can send buffer contents to an LLM, so
`~/.config/nvim/.codecompanion-enabled` gates it at startup. Add or remove that
file to toggle the plugin on one host without re-running init.

The npm-installed `claude-agent-acp` bridge lives in `~/.local/bin` and reuses
the existing Claude login. CodeCompanion does nothing without Neovim.

The npm-based AI CLIs (`opencode`, `opencode2`, and `copilot`) and the
`claude-agent-acp` bridge all need a Node runtime, so selecting any of them plans
Node and npm automatically; you do not also have to select Neovim. On Debian, the
Node 24 (NodeSource) build still ships with the Neovim component, so an AI-only
selection installs Debian's packaged Node, which is enough to provide npm.

Those CLIs install into `~/.local/bin` and are reachable by name only through the
`zsh` component, which puts `~/.local/bin` on `PATH` (via `~/.zshenv`) and defines
the `oc` / `oc2` / `oc2bg` aliases. With `zsh` deselected the binaries install but
are not on `PATH` by name and have no aliases; add `~/.local/bin` to `PATH`
yourself or run them by full path.

`oc2` pins `--standalone`, and as of this change so does the bare `opencode2`
name, so a mistyped launch cannot silently break attention notifications. The
notifier plugin runs inside the OpenCode server and its only pane signal is that
server's own `TMUX_PANE`, fixed at server start. `--standalone` makes the server
a child of the TUI, so one server maps to one pane. The shared background service
is a single process for every session in every pane and holds one pane id, so
with N panes, N-1 sessions notify the wrong pane. `oc2bg` is the deliberate
opt-in to that shared service: it saves roughly 864 MB per pane and gives up
per-pane notifications. See [Notifications](notifications.md#opencode).

### OpenCode V2 footer

OpenCode V2 loads a local CLI plugin from
`~/.config/opencode/v2-plugins/statusline/tui.tsx`. `cli.json` names its parent
package directory explicitly, which keeps it outside OpenCode's automatic V1
plugin discovery. It disables the stock `opencode.prompt.footer` and
`opencode-copilot-statusline.tui` renderers, then replaces
`prompt.footer.status`. This removes the command-palette hint and idle working
directory while keeping editor-file context in `prompt.footer.file`.

V2's local-path loader does not provide the `@opencode/plugin` and OpenTUI peer
packages advertised by its documentation. The managed `package.json` and lock
file install exact runtime versions under `~/.config/opencode/node_modules`.

The local renderer reproduces context usage and aggregate session cost. It
calls the `opencode-copilot-statusline@1.0.0` server RPC for the monthly limit,
but renders only the provider and used percentage after cost. The reset
countdown is intentionally omitted.

```text
󰉋 project   main •2 +14 -3  󰚩 build · gpt-5.6-sol · xhigh  󰥔 12m  󰓻 1 run    43.9K (4%) · $23.79 · GitHub Copilot 52%
```

| Pill | Data | Display rule |
| --- | --- | --- |
| Project | Project name, falling back to the working-directory basename | Always visible as the compact baseline |
| Git | Branch plus dirty-file count; additions and deletions when expanded | Hidden outside a repository |
| Identity | Active agent, shortened model ID, and effort variant | From 85 columns without Git or 125 columns with Git |
| Elapsed | Wall-clock age since session creation | From 115 columns without Git or 150 columns with Git |
| Subagents | Running child sessions and queued child prompts | Hidden when there is no active child work |
| Context and cost | Latest post-compaction context usage and aggregate family cost | Right-aligned when data exists |
| Provider limit | Active provider plus monthly used percentage | Last item; no reset countdown |

The plugin refreshes Git status after filesystem and branch events with a 250
ms debounce, and refreshes the Copilot limit every 60 seconds. During execution
the configured interrupt shortcut precedes the left pills and right-side usage
is hidden to preserve width; shell mode shows its exit guidance. Its colors
render from `.chezmoidata/palettes.yaml`, so changing `data.palette` keeps the
pills aligned with `gud-lucent`, tmux, Ghostty, and the rest of the rice.

The same palette overrides the built-in prompt metadata colors through
`agents.build.color` and `agents.plan.color`. Build renders in palette green;
Plan renders in palette blue.

An unselected component is excluded twice. Its targets are ignored by
`home/.chezmoiignore`, and its externals disappear from
`home/.chezmoiexternal.toml`.

The Git ignore file follows `git > ignore_global`. Claude and Codex config files
remain managed when either their hooks or the shared statusline needs them.
Ghostty follows `terminal > ghostty`; iTerm2 additionally requires macOS.

Standalone tool configs install regardless of component selection:
`~/.darglint`, `~/.flake8`, `~/.tflint.hcl`, `~/.markdownlint.yaml`, and
`~/.config/yamllint/config`. These belong to their command-line tools, not to
Neovim.

The Neovim component also installs the command-line tools behind its
integrations. The cross-platform package plan owns shell-visible
markdownlint-cli2, ShellCheck, yamllint, TFLint, Trivy, and Luacheck.

Mason owns language servers and editor-only Gitleaks. It installs missing
packages at startup but does not update or reconcile existing versions. See
[Neovim tooling](neovim.md) for the complete ownership model.

Neovim activates servers with `vim.lsp.config()` and `vim.lsp.enable()`,
including Docker's official Dockerfile and Compose server.

tenv reads `.terraform-version`, `.tfswitchrc`, `.tool-versions`, Terragrunt
constraints, and Terraform `required_version`. It verifies checksums and
HashiCorp signatures for missing Terraform versions.

The raw answer is stored as `componentSelection` and parsed into component
tables in `~/.config/chezmoi/chezmoi.toml`. Later applies reuse it without
prompting.

### Palette and install confirmation

The palette picker opens only when `colorscheme` is selected. Otherwise init
keeps the current value.

The picker preselects the current scheme. Its result is stored as
`data.palette`, with Dracula as the default.

The committed catalog renders every supported terminal and AI surface. It is
generated from the vendored base16 collection at authoring time, so apply does
not need Python, the submodule, or network access.

Set `DOTFILES_PALETTE=<id>` for a non-interactive selection. See
[Palette catalog](palettes.md) for generation and mapping details.

The final screen groups the deduplicated package plan by status: install,
update, then current. Colors honor `NO_COLOR`, and every line names its package
source.

Homebrew uses `brew outdated`, and APT uses `apt list --upgradable`, to report
real update state. Slower sources such as GitHub releases, npm, pip, LuaRocks,
externals, and Neovim plugins report only missing or installed state.

Package mode installs missing tools and updates the managed set. Config-only
mode still fetches selected chezmoi externals and runs safe finalizers, but
skips package managers, release binaries, language packages, `chsh`, and
Neovim synchronization.

On macOS, package mode upgrades outdated managed formulae and casks. On Debian,
`apt-get install` selects the current candidate version.

The plan appears on first init, when `DOTFILES_INSTALL_MODE` is set, or when the
`install_mode` action is selected. A normal later init reuses the saved mode.

When a component change or `cup` triggers the installer, its `[y/N]` prompt
shows the plan again. The package list appears when it matters, not every time
the picker opens.

Non-interactive init requires `DOTFILES_INSTALL_MODE=configs` or
`DOTFILES_INSTALL_MODE=packages`. Without one, chezmoi stops before apply.

An unattended package install also needs `DOTFILES_ASSUME_YES=1`. Without it, a
headless apply declines package changes and writes configuration only.

### Adding APT repositories

Some tools are not in Debian main and install from third-party APT repositories:
NodeSource (Node.js 24), Aqua Security (Trivy), and the GitHub CLI. The installer
adds each one only when a selected component needs it, and only if the host does
not already provide it.

On Debian, adding a repository asks first:

```text
dotfiles: add apt repository GitHub CLI (https://cli.github.com/packages)? [y/N]
```

Answer `y` to add it. Declining skips only that repository; the affected tool is
skipped with a warning instead of failing the run.

`DOTFILES_ASSUME_YES=1` adds the repositories without prompting. The Trixie
container and CI already set it, so unattended installs stay silent.

### Terminal (Ghostty, iTerm2)

Terminal configuration is opt-in. Ghostty is the cross-platform submenu
default; iTerm2 is macOS-only.

Both are gated by `home/.chezmoiignore`. iTerm2 also requires
`.chezmoi.os == "darwin"`, and its cask exists only in the macOS installer.
Selecting it on Debian is harmless.

#### Ghostty

Ghostty runs on macOS and Linux. Its config at
`~/.config/ghostty/config` is rendered from
`home/dot_config/ghostty/config.tmpl`, with OS-specific keys gated in the
template.

The selected palette lands at `~/.config/ghostty/themes/dotfiles.conf`. Hack
Nerd Font Mono provides the prompt and tmux glyphs.

A top-aligned, 40% quick terminal toggles with Command+backtick on macOS or
Control+backtick on Linux. macOS needs Accessibility permission. Linux needs a
desktop that implements the XDG GlobalShortcuts portal.

On macOS, Ghostty can also read
`~/Library/Application Support/com.mitchellh.ghostty/config`. These dotfiles
manage only the XDG path. Remove an old Application Support config or symlink
if it shadows the managed file.

On macOS, selecting Ghostty installs the Homebrew cask unless the app or cask is
already present.

##### Local overrides

`~/.config/ghostty/override.conf` holds machine-local Ghostty settings. The
managed config ends with `config-file = ?override.conf`, where the leading `?`
marks the include optional, so Ghostty starts clean when the file is absent and
nothing needs to be created for you. Included files load last, so the override
wins.

The file is not chezmoi-managed and is ignored by `chezmoi add`. See
[Local overrides](operation.md#local-overrides) for the shared pattern across
Ghostty, tmux, and Zsh.

##### Ghostty on Debian

Ghostty is not in Debian main and is no longer auto-installed. The third-party
apt repository it previously used goes subscription-only on 2026-10-01, so the
automated Debian path is dropped. Selecting the component still applies the
managed config; install the binary manually.

The free replacement is the community `mkasberg/ghostty-ubuntu` build (Trixie,
amd64 and arm64, per-asset SHA256). apt resolves the GTK dependencies from Trixie
main:

```zsh
arch=$(dpkg --print-architecture)
curl -fLO https://github.com/mkasberg/ghostty-ubuntu/releases/download/1.3.1-0-ppa2/ghostty_1.3.1-0.ppa2_${arch}_trixie.deb
sudo apt install ./ghostty_1.3.1-0.ppa2_${arch}_trixie.deb
```

The selection reaches the installer as `INSTALL_TERMINAL_GHOSTTY`; on Debian it
gates only the config, not a binary install. Other Linux installation options are
documented by [Ghostty](https://ghostty.org/docs/linux).

#### iTerm2

iTerm2 profiles are managed as Dynamic Profiles, not as a full preferences
plist. The source is `~/.config/iterm2/dotfiles.json`.

`scripts/install-iterm2.sh` links it into
`~/Library/Application Support/iTerm2/DynamicProfiles/`. This avoids committing
a `~/Library` tree or machine state such as window positions, bookmarks, and
updater timestamps.

Dynamic Profiles are read-only in the iTerm2 interface. Edit the JSON source.

On a fresh machine, iTerm2 loads the profiles from JSON. If matching regular
profiles already exist, iTerm2 keeps them because it rejects duplicate GUIDs
and will not run with an empty profile list. The committed JSON remains the
clean source of truth.

When selected, apply installs the iTerm2 cask, writes the JSON, creates the
link, pins the default-profile GUID, and sets a few application defaults.
Restart iTerm2 afterward; a running process can rewrite its preferences on
exit.

The AI API key stays in the macOS Keychain and is never synced. Profile behavior
lives in `home/dot_config/iterm2/dotfiles.json.tmpl`; generated palette objects
should not be edited independently.

## Changing components later

> One-time migration: if your `~/.config/chezmoi/chezmoi.toml` predates the `git`/`ai` submenus
> (it has flat `gitconfig`/`ai` booleans under `[data.components]`), run `chezmoi init` once
> before the next `apply` to regenerate the config with the nested `[data.components.git]` /
> `[data.components.ai]` tables. The templates `dig` into those tables, so an `apply` against a
> stale flat config errors until the schema is regenerated.
>
> The same applies to the `terminal` component: if your config still has the old bare `iterm2`
> boolean under `[data.components]` (from before `iterm2` became the `terminal > iterm2`
> sub-feature), run `chezmoi init` once to regenerate the `[data.components.terminal]` table.
> To keep iTerm2 selected through the migration, pick `terminal` with both `ghostty` and
> `iterm2` in the submenu (a plain re-init defaults `terminal` to `ghostty` only). Digging
> `terminal.iterm2` against the stale bare `iterm2` key does not error (it just reads the
> default), but the file gates track `terminal.*`, so `iterm2` config is unmanaged until the
> table is regenerated.

There are two ways to change the selection.

- Re-open the picker. The `ccomp` alias runs `chezmoi init --apply`:

  ```sh
  ccomp     # alias for: chezmoi init --apply
  ```

  With Gum installed, this reopens the picker with the current selection
  checked, then applies. Escape leaves the selection unchanged.

  A changed selection gives the `run_once` installer a new content hash, so new
  components install on the same run. An unchanged selection does not rerun
  package provisioning; use `cup` for that.

  Without Gum, `promptStringOnce` does not ask again while
  `componentSelection` is set. Clear the value first:

  ```sh
  sed -i.bak '/componentSelection/d' ~/.config/chezmoi/chezmoi.toml
  chezmoi init --apply
  ```

- Or edit `~/.config/chezmoi/chezmoi.toml` directly and adjust the booleans, then
  `chezmoi apply`:

  ```toml
  [data]
      palette = "dracula"
      zshTheme = "gud"
      installMode = "configs"
      gitName = "Your Name"
      gitEmail = "you@example.com"

  [data.components]
      zsh = true
      tmux = false
      neovim = true

  [data.components.git]
      config = false
      personal = false
      ignore_global = true

  [data.components.ai]
      codecompanion = false
      claude_hooks = false
      statusline = false

  [data.components.terminal]
      ghostty = true
      iterm2 = false
  ```

  Keep the bare `zsh`/`tmux`/`neovim` keys above the `[data.components.git]`,
  `[data.components.ai]`, and `[data.components.terminal]` tables - once a TOML sub-table is
  opened, later bare keys fall into it.

Turning a component off removes unmodified managed files on the next apply.
Locally edited files remain in place. Turning a component on writes its files
and fetches its plugins.

With `git > personal` enabled, `gitName` and `gitEmail` live only in the host's
chezmoi config. They are rendered into mode-600 `~/.gitconfig.personal` and
never stored in the repository.

The installer does not print or copy an existing Git configuration.

The `run_once` installer embeds component booleans, so a selection change
reruns it. Packages are still limited to `installMode = "packages"` and require
confirmation.

Because the installer is content-hashed, applying an unchanged selection does
not upgrade packages. Use `cup` to force that work without reopening the picker.

To enable CodeCompanion later, set it to true under `[data.components.ai]` or
select it in the AI submenu, then apply. Choose package mode if the ACP bridge
is not installed.

### Updating packages

`cup` installs anything missing and upgrades the managed set (`brew upgrade` on macOS,
`apt`-to-candidate on Debian), so the plan's "to update" tier clears, without re-opening the
component picker:

```sh
cup     # chezmoi state delete-bucket --bucket=scriptState; chezmoi apply
```

`cup` clears the installer's `run_once` state and applies again. It requires
package mode and shows the normal confirmation; use `DOTFILES_ASSUME_YES=1`
headlessly.

A plain apply deliberately skips this work so config-only syncs stay fast.

### Changing the palette

Re-run the picker and check `colorscheme`, or set `data.palette` directly.

```sh
ccomp     # re-opens the picker; check "colorscheme" in the menu
```

With gum, checking `colorscheme` opens a single-select list of the catalog with the current
scheme pre-selected; leaving it unchecked keeps the current palette. Or edit the config and apply:

```toml
[data]
    palette = "gruvbox-dark"
```

Valid ids are the `paletteOrder` keys in `home/.chezmoidata/palettes.yaml`. To add a scheme, add it to
`CURATED` in `scripts/build-palettes.py`, run `python3 scripts/build-palettes.py`, and commit the
regenerated catalog (CI's `build-palettes.py --check` fails if the commit is stale).

### Changing the Zsh prompt

Gud remains the default prompt and follows the selected terminal ANSI palette. To use another
existing Oh My Zsh theme or a readable theme file, edit `data.zshTheme` and apply:

```toml
[data]
zshTheme = "robbyrussell"
# zshTheme = "~/src/my-prompt.zsh-theme"
```

An invalid name or unreadable path prints a warning and falls back to Gud.
