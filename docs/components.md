<!-- docs/components.md -->
# Components

## Table of Contents

- [Choosing components](#choosing-components)
  - [Palette and install confirmation](#palette-and-install-confirmation)
  - [Adding APT repositories](#adding-apt-repositories)
  - [Sub-feature submenus (git, ai, terminal)](#sub-feature-submenus-git-ai-terminal)
  - [Writing-quality agent skills](#writing-quality-agent-skills)
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

The persisted `[data.components.*]` values preserve the resolved host state.
Older `all` selections migrate to `default`. Retired `all+` selections migrate
to explicit selections for all six current components without replaying setup
actions. The removed `opencode2` sub-feature migrates to canonical
`ai.opencode` V2 while old nested Git, AI, and terminal selections remain intact.

Without Gum, the same choices appear as a numbered prompt:

```text
Components to install:
  1) Zsh                oh-my-zsh, plugins, custom functions, aliases
  2) tmux               tmux + plugins (tpm, resurrect, sensible, yank)
  3) Neovim             Neovim, lazy.nvim, language servers, linters
  4) Git                managed config and independent global ignore
  5) AI tools           OpenCode V2, hooks, statusline, Copilot, CodeCompanion
  6) terminal emulators independent Ghostty and iTerm2 configuration

Setup actions:
  7) theme        choose the shared color theme (unchecked keeps it)
  8) package mode choose configs-only or package installation (unchecked keeps it)

  default  the default component set (1 2 3 4)

Enter numbers (e.g. "1 3"), type default, or press Enter for default (1 2 3 4)
```

Both interfaces persist their selection and resolve the same
`[data.components]` tables.

| Input | Selects |
| --- | --- |
| Numbers (e.g. `1 3`) | Any subset; spacing/order don't matter - `1 3`, `13`, and `3 1` are equivalent |
| Enter | The default, `1 2 3 4` (zsh + tmux + neovim + git; no AI tools) |
| `default` | The default set (`1 2 3 4`) |

Component rows and setup-action rows are separate. Actions reopen a picker for
that init and never become component booleans.

The component list in `home/.chezmoi.toml.tmpl` is the source of truth for both
interfaces. Set `DOTFILES_NO_TUI=1` to force the numbered prompt.

`theme` and `package mode` are init-time actions. They live outside
`[data.components]` and reopen the relevant picker when selected.

### Sub-feature submenus (git, ai, terminal)

`git`, `ai`, and `terminal` open a second picker for sub-features. Their values
live in nested tables such as `[data.components.git]`; the parent is considered
on when any child is true.

Git is in the default component set. AI and terminal configuration are opt-in.

| Component | Sub-feature | Target | Submenu default | Notes |
| --- | --- | --- | --- | --- |
| `git` | `config` | `~/.gitconfig` | off | generic Git behavior plus an unmanaged `~/.gitconfig.override` include; creates an empty mode-600 override only when absent |
| `git` | `ignore_global` | `~/.gitignore_global` | on | independent of the managed Git config |
| `ai` | `claude_hooks` | `~/.claude/settings.json` (merge) | off | merges the Claude notify hooks |
| `ai` | `codex_hooks` | `~/.codex/config.toml` (merge) | off | merges the Codex notify hook + `tui.notifications` |
| `ai` | `statusline` | `~/.claude/settings.json` + `~/.codex/config.toml` (merge) | off | Claude renderer plus a matching selected-palette Codex theme; keeps those files managed when notify hooks are off |
| `ai` | `opencode` | OpenCode V2 (`@opencode/cli`) + V2 config + notifier bridge | on when AI is selected | isolated npm prefix, managed wrapper, native permissions, and exact-pinned statusline plugin |
| `ai` | `copilot` | GitHub Copilot CLI (`@github/copilot` npm, `prerelease` tag) | off | npm-only channel (no Homebrew/apt); binary into `~/.local`; needs Node 22+ |
| `ai` | `codecompanion` | CodeCompanion.nvim + `claude-agent-acp` bridge | off | selecting it also enables and installs the Neovim component |
| `terminal` | `ghostty` | Ghostty config + quick-terminal dropdown | on | macOS and Linux |
| `terminal` | `iterm2` | iTerm2 Dynamic Profiles | off | macOS only; hidden in the submenu on non-macOS (data key still emitted for column parity), also gated in `home/.chezmoiignore` |

Gum preselects the parent's current sub-features on a re-init. A new parent uses
its documented defaults. The typed submenu behaves the same way, with Enter
accepting the defaults.

Sub-feature descriptions use `/` instead of commas in the Gum option string.
Gum treats commas as selection separators, which otherwise breaks preselection.
The submenu only appears when its parent is selected.

Nothing AI-related installs unless the AI component is selected.

### Writing-quality agent skills

Selecting any `ai` sub-feature also installs `unslop-code`, `unslop-text`,
`unslop-ui`, and the explicit-only `humanizer`. There is no separate submenu
choice. A single canonical store under `~/.local/share/agent-skills` feeds
per-skill links in both `~/.claude/skills` and `~/.agents/skills`.

Claude Code and CodeCompanion use the Claude root. Codex, OpenCode V2, and
GitHub Copilot use the Agent Skills root. OpenCode may discover both roots, but
both links point to the same canonical directories and resolve to one effective
ID per skill.

Humanizer never runs implicitly. An explicit humanization applies Humanizer
first and `unslop-text` second. OpenCode also receives prompt-only `/unslop` and
`/humanize` commands. See [Cross-harness agent skills](agent-skills.md) for pins,
licenses, invocation, update audit, and threat boundaries.

CodeCompanion can send buffer contents to an LLM, so
`~/.config/nvim/.codecompanion-enabled` gates it at startup. Add or remove that
file to toggle the plugin on one host without re-running init.

The npm-installed `claude-agent-acp` bridge lives in `~/.local/bin` and reuses
the existing Claude login. Selecting CodeCompanion automatically enables
Neovim before the package plan and confirmation are shown.

The npm-based AI CLIs (`opencode2` and `copilot`) and the
`claude-agent-acp` bridge all need a Node runtime, so selecting any of them plans
Node and npm automatically. On Debian, any such selection enables the
NodeSource Node.js 24 repository. If repository setup, package installation, or
Node 24 verification fails, only npm-dependent steps are skipped. Python,
LuaRocks, Git externals, and editor updates continue.

The OpenCode wrapper, Copilot CLI, and ACP bridge live in `~/.local/bin`. They are
reachable by name only through the `zsh` component, which puts that directory on
`PATH` (via `~/.zshenv`) and defines the `oc` / `oc2` / `oc2bg` aliases. With
`zsh` deselected they are not on `PATH` by name and have no aliases.

`oc` launches OpenCode V2 with `--standalone`. `oc2` remains as a temporary
alias, and `oc2bg` explicitly uses the shared background service. The
notifier plugin runs inside the OpenCode server and its only pane signal is that
server's own `TMUX_PANE`, fixed at server start. `--standalone` makes the server
a child of the TUI, so one server maps to one pane. The shared background service
is a single process for every session in every pane and holds one pane id, so
with N panes, N-1 sessions notify the wrong pane. `oc2bg` is the deliberate
opt-in to that shared service: it saves roughly 864 MB per pane and gives up
per-pane notifications. See [Notifications](notifications.md#opencode).

The managed `~/.local/bin/opencode2` wrapper executes the isolated binary at
`~/.local/share/opencode2/bin/opencode2` and sets that directory as the npm
prefix. `opencode2 update` and `opencode2 upgrade` add `--method npm` unless an
explicit method is present before `--`. Every other argument is passed through
unchanged. Both installer and wrapper canonicalize their paths and reject a
prefix whose binary resolves back to the managed wrapper.

`~/.config/opencode/opencode.jsonc` is merge-managed. Chezmoi reasserts the
schema, built-in agent colors, and exact-pinned V2 plugin list while preserving
unknown top-level keys and comments. A fresh host receives native ordered
`permissions`; only the exact old generated `permission` block is migrated.
Customized V1 or V2 policies remain untouched. Within `agents`, only
`build.color` and `plan.color` are managed; custom agents and every other
built-in field or comment survive unchanged.

`cli.json` enables session tabs and uses `Ctrl+G` as a 1500 ms leader.
`<leader>h` and `<leader>l` move between tabs, while `<leader>t` opens the
session list. `Home` moves to the first message, freeing `Ctrl+G` for the leader,
and the old `<leader>t` theme switch is disabled.

### OpenCode V2 footer

OpenCode V2 loads a local CLI plugin from
`~/.config/opencode/v2-plugins/statusline/tui.tsx`. `cli.json` names its parent
package directory explicitly, which keeps it outside automatic server-plugin
discovery. It disables the stock `opencode.prompt.footer` and
`opencode-copilot-statusline.tui` renderers, then replaces
`prompt.footer.status`. This removes the command-palette hint and idle working
directory while keeping editor-file context in `prompt.footer.file`.

V2's local-path loader does not provide the `@opencode/plugin` and OpenTUI peer
packages advertised by its documentation. Package mode installs a matching,
unlocked runtime under `~/.local/share/opencode2/plugin-runtime` and links its
`node_modules` into `~/.config/opencode`. Chezmoi does not track the runtime,
manifest, lockfile, or dependency tree.

The local renderer reproduces context usage and aggregate session cost. It
calls the `opencode-copilot-statusline@1.0.0` server RPC for the monthly limit,
but renders only the provider and used percentage. The reset countdown is
intentionally omitted. Context, cost, and provider usage are separate
left-aligned pills after the activity pills.

```text
󰉋 project   main •2 +14 -3  ⠋ 󰚩 build · gpt-5.6-sol · xhigh  󰥔 12m  O 1 run  󰍛 43.9K (4%)  ≈ $23.79  󰊤 GitHub Copilot 52%
```

| Pill | Data | Display rule |
| --- | --- | --- |
| Project | Project name, falling back to the working-directory basename | Always visible as the compact baseline |
| Git | Branch plus dirty-file count; additions and deletions when expanded | Hidden outside a repository |
| Identity | Active agent, shortened model ID, and effort variant | From 85 columns without Git or 125 columns with Git |
| Foreground spinner | Cyan single-cell animation before the identity pill | While the active session runs model or tool work; hidden while idle, waiting for input, or in shell mode |
| Elapsed | Wall-clock age since session creation | From 115 columns without Git or 150 columns with Git |
| Subagents | Running child sessions and queued child prompts | Orange single-cell animation while children run; static icon for queued-only work; hidden without child work |
| Context | Latest post-compaction context usage | Left-aligned pill; survives longest among usage pills |
| Estimated cost | Aggregate session-family cost | Left-aligned pill; hidden before context at narrow widths |
| Provider limit | Active provider plus monthly used percentage | Left-aligned pill; hidden first at narrow widths; no reset countdown |

The plugin refreshes Git status after filesystem and branch events with a 250
ms debounce, and refreshes the Copilot limit every 60 seconds. During execution
the configured interrupt shortcut precedes the pills while the latest usage
values remain visible when width permits. Shell mode shows its exit guidance. Its colors
render from `.chezmoidata/palettes.yaml`, so changing `data.palette` keeps the
pills aligned with `gud-lucent`, tmux, Ghostty, and the rest of the rice.

The spinner clock exists only while a visible foreground spinner or running
child needs it. Both animations can appear together. Foreground and subagent
frames update only their single-cell glyphs, leaving Git, context, cost, and
quota calculations off the animation path.

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

The palette picker opens only when the `theme` setup action is selected.
Otherwise init keeps the current value.

With Gum, the picker lists human-readable names, supports type-to-filter, and
preselects the current scheme. Without Gum, a numbered list replaces the
searchable picker. Interactive use never requires memorizing a palette ID. The
result is stored as `data.palette`, with Dracula as the default.

The committed catalog renders every supported terminal and AI surface. It is
generated from the vendored base16 collection at authoring time, so apply does
not need Python, the submodule, or network access.

Set `DOTFILES_PALETTE=<id>` for a non-interactive selection. See
[Palette catalog](palettes.md) for generation and mapping details.

The final screen groups the deduplicated package plan by status: install,
update, then current. Colors honor `NO_COLOR`, and every line names its package
source and whether it floats or is pinned.

The pre-approval plan uses command and path probes. It does not invoke
Homebrew, APT, npm, pip, or LuaRocks. After approval, Homebrew refreshes its
metadata and checks its managed inventory; APT refreshes metadata before
installing only the selected package names.

Package mode installs missing tools and updates the managed set. Config-only
mode still clones missing selected chezmoi externals and runs safe finalizers,
but skips external refreshes, package managers, release binaries, language
packages, `chsh`, and Neovim synchronization.

Missing selected Git externals are part of chezmoi's configuration payload.
Chezmoi clones them while materializing selected configuration, before the
`run_once` installer. Existing checkout refreshes are different: package mode
checks status, tracking configuration, and declared URL after package approval,
then fetches only the matching tracking remote and fast-forwards clean branches.

On macOS, package mode upgrades outdated managed formulae and casks. An
existing Ghostty app that is not managed by Homebrew is reported as a manual
exception. On Debian, individual `apt-get install` calls select the current
candidate version without running a distribution upgrade. Ghostty remains a
manual install there too.

Floating npm CLIs, OpenCode runtime dependencies, Neovim Python providers,
LuaRocks tools, checksum-verified GitHub release binaries, Lazy plugins,
Treesitter parsers, and installed Mason packages update on every approved
package run. Selected chezmoi Git externals and installer-owned TPM repositories
advance only when their checkout is clean and the remote change is a
fast-forward. Dirty, detached, ahead, or diverged checkouts are skipped with a
warning.

Exact versions remain source-controlled. Package mode reasserts the pinned
tree-sitter CLI instead of advancing it. OpenCode's plugin API follows the
installed CLI version while its UI peer dependencies float within npm's
compatible ranges. The pinned OpenCode statusline plugin reference, pre-commit revisions, and
palette submodule commit change only through repository updates. Initializing
that exact palette submodule commit happens only after package approval.

The plan appears on first init, when `DOTFILES_INSTALL_MODE` is set, or when the
`package mode` setup action is selected. A normal later init reuses the saved mode.

When a component change triggers the installer, its `[y/N]` prompt shows the
plan again. `cup` uses a scoped re-init that keeps the component choices and
opens the same plan and mode confirmation.

Non-interactive init requires `DOTFILES_INSTALL_MODE=configs` or
`DOTFILES_INSTALL_MODE=packages`. Without one, chezmoi stops before apply.

An unattended package install also needs `DOTFILES_ASSUME_YES=1`. Without it, a
headless apply declines package changes and writes configuration only.

An unattended recurring update is deliberately stricter. It requires all
three variables so a plain automation apply cannot accidentally advance
`packageRun`:

```sh
DOTFILES_PACKAGE_UPDATE=1 \
DOTFILES_INSTALL_MODE=packages \
DOTFILES_ASSUME_YES=1 \
  chezmoi init --apply --no-tty
```

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

  ```zsh
  ccomp     # alias for: chezmoi init --apply
  ```

  With Gum installed, this reopens the picker with the current selection
  checked, then applies. Escape leaves the selection unchanged.

  A changed selection gives the `run_once` installer a new content hash, so new
  components install on the same run. An unchanged selection does not rerun
  package provisioning; use `cup` for that.

  Without Gum, `promptStringOnce` does not ask again while
  `componentSelection` is set. Clear the value first:

  ```zsh
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
      packageRun = 0
  [data.components]
      zsh = true
      tmux = false
      neovim = true

  [data.components.git]
      config = false
      ignore_global = true

  [data.components.ai]
      codecompanion = false
      claude_hooks = false
      codex_hooks = false
      statusline = false
      opencode = true
      copilot = false

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

With `git > managed config` enabled, the installer creates an empty mode-600
`~/.gitconfig.override` only when the file does not exist. The managed Git
configuration contains no author identity, signing key, or work-specific path.
Use private aliases in the override to set repository-local identities. The
global ignore remains independently selectable.

The installer does not print, inspect, or overwrite an existing Git override.

The `run_once` installer embeds component booleans, so a selection change
reruns it. Packages are still limited to `installMode = "packages"` and require
confirmation.

Because the installer is content-hashed, applying an unchanged selection does
not upgrade packages. Use `cup` to open only the package plan and mode
confirmation. Selecting packages increments `data.packageRun`, which gives the
installer a new content hash without clearing the `scriptState` bucket.

To enable CodeCompanion later, set it to true under `[data.components.ai]` or
select it in the AI submenu, then apply. The selection also sets
`components.neovim = true`; choose package mode to install Neovim and the ACP
bridge.

### Updating packages

`cup` installs anything missing and updates the selected floating set without
reopening the component picker:

```zsh
cup     # DOTFILES_PACKAGE_UPDATE=1 chezmoi init --apply
```

The package choice increments the persisted `packageRun` integer and applies.
Choosing configs leaves the integer unchanged. Ordinary apply, normal re-init,
and `DOTFILES_INSTALL_MODE` by itself never increment it. The three-variable
headless update shown above increments it once per successful re-init.

A plain apply deliberately skips this work so config-only syncs stay fast.

### Changing the palette

Re-run the picker and check `theme`, or set `data.palette` directly.

```zsh
ccomp     # re-opens the picker; check "theme" in the setup actions
```

With Gum, checking `theme` opens a single-select list of the catalog with the current
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
