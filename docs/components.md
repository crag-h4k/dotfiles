<!-- docs/components.md -->
# Components

## Table of Contents

- [Choosing components](#choosing-components)
  - [Sub-feature submenus (git, ai, terminal)](#sub-feature-submenus-git-ai-terminal)
  - [terminal (ghostty, iterm2)](#terminal-ghostty-iterm2)
    - [ghostty](#ghostty)
    - [iterm2](#iterm2)
- [Changing components later](#changing-components-later)

## Choosing components

With [`gum`](https://github.com/charmbracelet/gum) installed, `chezmoi init` shows a checkbox
TUI: space toggles a component, enter confirms, esc cancels. On re-runs your currently-enabled
components come pre-checked (and the header also lists them), seeded from the persisted
`[data.components.*]` resolution so the `all` / `all+` keyword forms are reflected too. `gum` is
installed as part of the macOS base toolchain and Debian base
package set on first apply (and is included in the Quick start bootstrap), so it is available
from the second `chezmoi init` onward (see
[Changing components later](#changing-components-later)).

Without `gum` - if you skipped the bootstrap install - it falls back to a typed numbered menu:

```text
Components to install:
  1) zsh      oh-my-zsh, plugins, custom functions, aliases
  2) tmux     tmux + plugins (tpm, resurrect, sensible, yank)
  3) neovim   neovim, lazy.nvim, language servers, linters
  4) git      git config files (config, personal, ignore_global)
  5) ai       AI tools (claude_hooks, codex_hooks, statusline, codecompanion)
  6) terminal terminal emulator config (ghostty, iterm2)

  all   the default set (1 2 3 4)
  all+  everything, adds ai, terminal

Enter numbers (e.g. "1 3"), a keyword above, or press Enter for default (1 2 3 4)
```

Both paths resolve to the same `componentSelection` string and the same `[data.components]`
tables. For the typed menu:

- Numbers: any subset (e.g. `1 3` for zsh + neovim). Spacing and order do not matter - `1 3`,
  `13`, and `3 1` are equivalent.
- Enter: the default, `1 2 3 4` (zsh + tmux + neovim + git; no AI tools).
- `all`: the default set (`1 2 3 4`).
- `all+`: everything, adding the AI tools and the `terminal` component. Like the other
  submenus, `all+` takes each parent at its default sub-features only, so `terminal` comes on
  with `ghostty` (its default) but not `iterm2`; add `iterm2` by selecting it in the submenu.

The component list is the single source of truth in `.chezmoi.toml.tmpl`; the gum options and
the typed menu are both generated from it, so adding a component is a one-line edit there. Set
`DOTFILES_NO_TUI=1` to force the typed menu even when gum is installed.

### Sub-feature submenus (git, ai, terminal)

`git`, `ai`, and `terminal` are not plain booleans - each opens a second checkbox to pick its
sub-features (so they are stored as the nested tables `[data.components.git]`,
`[data.components.ai]`, and `[data.components.terminal]`, where "on" means any sub-feature is
true):

- `git`: `config` (`~/.gitconfig`), `personal` (`~/.gitconfig.personal`), `ignore_global`
  (`~/.gitignore_global`). `git` is in the default set, but the submenu pre-selects only
  `ignore_global` - so by default you get `~/.gitignore_global` and not `~/.gitconfig`
  (identical to the old behavior).
- `ai`: `claude_hooks` (merges the Claude notify hooks into `~/.claude/settings.json`),
  `codex_hooks` (merges the Codex notify hook + `tui.notifications` into
  `~/.codex/config.toml`), `statusline` (installs a gud, Dracula-family, Claude statusline
  plus a Codex gud theme; this is what makes `~/.claude/settings.json` and
  `~/.codex/config.toml` managed even when the notify hooks are off; opt-in and default-off,
  not in the `all` set), `codecompanion` (CodeCompanion.nvim + the `claude-agent-acp` bridge).
  `codecompanion` is listed last because it is the heaviest sub-feature - it pulls in node,
  npm, and the npm-installed bridge. `ai` stays off by default; if picked, the submenu still
  defaults to `codecompanion`.
- `terminal`: `ghostty` (Ghostty config + quick-terminal dropdown, macOS and Linux) and
  `iterm2` (iTerm2 Dynamic Profiles, macOS only). `terminal` stays off by default; if picked,
  the submenu defaults to `ghostty`. `iterm2` carries an `os` tag, so the submenu hides it on
  non-macOS (the data key is still emitted for column parity, and the file gate in
  `.chezmoiignore` also enforces darwin).

With `gum` the submenu is a nested checkbox whose `--selected` seed pre-checks the parent's
currently-enabled sub-features (read from the persisted `[data.components.<parent>]` table), so a
re-init shows what is on already ticked; a fresh init, or a parent just turned on, pre-checks the
sub-defaults instead. Commas in a sub-feature description are swapped to `/` for the gum option
string, because `gum choose` splits `--selected` on commas and would otherwise never pre-check a
comma-bearing entry (this is why `codecompanion` used to always show unchecked). Without `gum` (or
under `DOTFILES_NO_TUI`) it falls back to a typed sub-menu, and Enter / no-tty takes the defaults.
The submenu only appears when its parent component is selected.

`ai` keeps AI tooling opt-in, so nothing AI-related installs unless you ask for it.
`codecompanion` ships buffer contents to an LLM, so a sentinel file
(`~/.config/nvim/.codecompanion-enabled`) gates the plugin at startup; you can `touch`/`rm` it
to flip per-host without re-running `init`. The `claude-agent-acp` bridge is installed via npm
into `~/.local/bin`, and the chat reuses your existing `claude` login (no token to store).
`codecompanion` without `neovim` is a no-op.

A component (or sub-feature) that is off is excluded two ways: its target files are added to
`.chezmoiignore` so `chezmoi apply` never writes them, and its plugin externals are dropped
from `.chezmoiexternal.toml` so they are never fetched. `~/.gitignore_global` follows the
`git > ignore_global` sub-feature (on by default), `~/.claude/settings.json` is managed when
either `ai > claude_hooks` or `ai > statusline` is on, `~/.codex/config.toml` is managed when
either `ai > codex_hooks` or `ai > statusline` is on, `~/.config/ghostty` follows
`terminal > ghostty` (on when `terminal` is picked), and `~/.config/iterm2` follows
`terminal > iterm2` and `darwin` (macOS only). The base files install regardless of selection:
`~/.tfswitch.toml` and the tool linter configs (`~/.darglint`, `~/.flake8`, `~/.tflint.hcl`,
`~/.markdownlint.yaml`, `~/.config/yamllint/config`). Those linter configs are plain tool
configs, not neovim's, so they live at each tool's own path and install even without the neovim
component.

The raw answer is stored as `componentSelection` and parsed into `[data.components]` booleans
in `~/.config/chezmoi/chezmoi.toml`, reused on every subsequent `chezmoi apply` without
re-prompting.

### terminal (ghostty, iterm2)

`terminal` is opt-in (not in the default set) and carries terminal-emulator config as two
sub-features: `ghostty` (cross-platform, the submenu default) and `iterm2` (macOS only). Both
are gated at the file layer in `.chezmoiignore`; `iterm2` also gates on
`.chezmoi.os == "darwin"` and its cask install runs only in the macOS arm of
`scripts/install.sh`, so selecting `iterm2` on Debian is a harmless no-op.

#### ghostty

Ghostty runs on macOS and Linux. Its config lives at `~/.config/ghostty/config`, templated
from `dot_config/ghostty/config.tmpl` so the macOS-only keys and the global-shortcut modifier
are gated per OS. The palette is the single source of color truth in
`~/.config/ghostty/themes/gud-theme.conf` - a Dracula-family "gud" variant that matches the
tmux status line and the nvim `dracula` colorscheme, so the whole terminal reads as one theme.
The font is Hack Nerd Font Mono, so the prompt and tmux status-line glyphs render. A
Yakuake-style quick-terminal dropdown (position top, size 40%, autohide) toggles from a global
shortcut: `global:cmd+grave_accent=toggle_quick_terminal` on macOS (needs Accessibility
permission), and `global:ctrl+grave_accent=toggle_quick_terminal` on Linux (needs a desktop
that implements the XDG GlobalShortcuts portal).

On macOS, Ghostty also reads a config-shadow at `~/Library/Application
Support/com.mitchellh.ghostty/config`. The dotfiles manage only the XDG path
(`~/.config/ghostty`); if that Application Support path exists (for example a leftover symlink
from an older setup), remove it so it cannot override this config.

Selecting `ghostty` installs the binary as well as the config, gated by
`INSTALL_TERMINAL_GHOSTTY` (dug from `terminal.ghostty`). On macOS `chezmoi apply` installs the
Homebrew cask (`brew install --cask ghostty`), guarded to skip if `/Applications/Ghostty.app`
already exists or the cask is already present. On Debian it installs the config only and does
not fetch the binary: Ghostty has no official Debian apt package (the project ships source
builds plus community repos; Ubuntu 26.04+ has it, Debian does not), and this profile is a
headless trixie container where a GUI terminal is not provisioned. To install Ghostty on a real
Linux desktop, use the Ghostty Linux docs (<https://ghostty.org/docs/linux>) or a community
Debian repo such as <https://debian.griffo.io>, then let the managed config apply on top.

#### iterm2

Profiles are managed as iTerm2 **Dynamic Profiles** (JSON), not a full prefs plist. The JSON is
kept at a clean, chezmoi-managed path, `~/.config/iterm2/dotfiles.json`, and
`scripts/install-iterm2.sh` symlinks it into the one directory iTerm2 reads dynamic profiles
from (`~/Library/Application Support/iTerm2/DynamicProfiles/`) - so the repo carries no
`~/Library` tree. iTerm2 loads dynamic profiles non-destructively, with no prefs-folder
redirect and no machine-state cruft (window frames, last-directory bookmarks, updater
timestamps) in the repo. Dynamic profiles are read-only in the iTerm2 UI; edit the JSON to
change them.

On a fresh machine the profiles load straight from the JSON. On a machine that already had them
as regular profiles, iTerm2 keeps the regular copies (it rejects a dynamic profile whose Guid
matches an existing one, and will not run with an empty profile list); the committed JSON still
serves as source of truth and a clean, diffable snapshot.

When selected on a Mac, `chezmoi apply` installs the iTerm2 cask
(`brew install --cask iterm2`) and writes the JSON, then `scripts/install-iterm2.sh` creates
the symlink, pins the default-profile Guid, and sets a few app-level behavior toggles via
`defaults write`. Restart iTerm2 to pick up the global `defaults` (a running iTerm2 rewrites its
prefs on quit). The AI API key lives in the macOS Keychain and is intentionally not synced.

To regenerate the committed profiles from your current iTerm2 profiles (re-scrub any
machine-specific fields such as `Working Directory` afterward):

```bash
python3 - <<'EOF'
import json, plistlib, subprocess, os
raw = subprocess.run(["defaults", "export", "com.googlecode.iterm2", "-"],
                     capture_output=True).stdout
d = plistlib.loads(raw)
dst = os.path.expanduser("~/.local/share/chezmoi/dot_config/iterm2/dotfiles.json")
json.dump({"Profiles": d["New Bookmarks"]}, open(dst, "w"),
          indent=2, sort_keys=True)
EOF
```

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

Two ways:

- Re-open the picker. The `ccomp` alias runs `chezmoi init --apply`:

  ```sh
  ccomp     # alias for: chezmoi init --apply
  ```

  With `gum` installed (it is, after the first macOS apply) this re-opens the gum TUI with your
  current selection pre-checked, then applies. The gum picker is not gated by `promptStringOnce`, so
  it re-prompts every time - no need to clear `componentSelection` first. Cancelling the picker
  (Esc) keeps the current selection unchanged.

  Without `gum`, `chezmoi init` falls back to `promptStringOnce`, which will not re-prompt while
  `componentSelection` is set; clear it first, then re-init:

  ```sh
  sed -i.bak '/componentSelection/d' ~/.config/chezmoi/chezmoi.toml
  chezmoi init --apply
  ```

- Or edit `~/.config/chezmoi/chezmoi.toml` directly and adjust the booleans, then
  `chezmoi apply`:

  ```toml
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

Turning a component off removes its files on the next apply (its targets are now ignored);
turning one on writes them and fetches its plugins. Unmodified managed files are removed
cleanly. A file you edited locally is left in place rather than deleted, so back it up first if
you want it gone.

Enabling a component that installs packages (e.g. `ai`) also re-runs the installer
automatically: `run_once_after_00-install.sh` embeds the component booleans, so flipping one
changes the script's rendered content and chezmoi re-runs it on the next apply, installing the
newly selected tools. If it does not re-run for some reason, force it:

```sh
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

So to enable the AI tools after the fact: set `codecompanion = true` under `[data.components.ai]`
in `~/.config/chezmoi/chezmoi.toml` (or re-run the menu, include `5`, and check `codecompanion`
in the submenu), then `chezmoi apply`. That installs the Claude Code ACP bridge and provisions
the CodeCompanion sentinel - no full reinstall needed.
