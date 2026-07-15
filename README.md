# dotfiles

Single-repo dotfile deployment using [chezmoi](https://chezmoi.io). `~` is the
only repo you need to clone on a new host.

Consolidates my zsh, tmux, and Neovim configuration (formerly split across
`gud-zsh`, `gud-vim`, `gud-tmux`) into one chezmoi source tree. Upstream plugins
(oh-my-zsh, tpm, `tmux-*`, `zsh-*`) come from chezmoi externals, so nothing is
vendored and plugins refresh on their own.

chezmoi owns component selection. You pick zsh, tmux, neovim, and gitconfig once
at `chezmoi init`. The choice persists in `~/.config/chezmoi/chezmoi.toml`.
`chezmoi apply` then writes only the selected components' files and keeps them
current. No wrapper script and no path juggling.

## Table of Contents

- [Quick start (new host)](#quick-start-new-host)
- [Choosing components](#choosing-components)
- [Changing components later](#changing-components-later)
- [How it works](#how-it-works)
- [What lives where](#what-lives-where)
- [Notifications](#notifications)
- [Daily operation](#daily-operation)
- [Supported platforms](#supported-platforms)
- [Uninstall](#uninstall)

## Quick start (new host)

Install `gum` first so the component picker shows a checkbox TUI, then
bootstrap chezmoi:

```sh
# macOS
command -v gum >/dev/null || brew install gum
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k

# Debian Trixie
command -v gum >/dev/null || { sudo apt-get update && sudo apt-get install -y gum; }
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply crag-h4k
```

Without `gum` the picker falls back to a typed numbered menu - still works,
just less interactive.

The chezmoi bootstrap line:

1. Installs `chezmoi` if missing.
1. Clones this repo into `~/.local/share/chezmoi/`.
1. Prompts for which components to install (gum TUI or typed menu) and saves
   the answer to `~/.config/chezmoi/chezmoi.toml`.
1. Runs `chezmoi apply`, which:
   - Fetches the upstream plugins declared in `.chezmoiexternal.toml` for the
     selected components and drops them under `~/.zsh/ohmyzsh`,
     `~/.zsh/custom/plugins/*`, `~/.tmux/plugins/*`.
   - Places the selected components' files: `~/.zshrc`, `~/.zshenv`,
     `~/.tmux.conf` as real files and populates `~/.zsh/`, `~/.tmux/`,
     `~/.config/nvim/` with the tracked config.
   - Places the linter configs at their own conventional paths (`~/.darglint`,
     `~/.flake8`, `~/.tflint.hcl`, `~/.markdownlint.yaml`, `~/.config/yamllint`).
   - Runs `run_before_00-backup.sh` first, which snapshots the previous
     (pre-apply) version of your configs into `~/.dotfiles-backup/<timestamp>/`
     before anything is overwritten - every managed file plus colocated
     non-managed state / local additions (e.g. `lazy-lock.json`, a hand-added
     `~/.tmux/conf.d/*.conf`). Re-fetchable git externals (oh-my-zsh, tmux/zsh
     plugins) and app-state dirs with secrets/logs (`~/.claude`, `~/.codex`) are
     skipped. Runs on every apply; keeps the most recent `DOTFILES_BACKUP_KEEP`
     (default 20) snapshots.
   - Runs `run_once_after_00-install.sh`, which exports the component selection
     as `INSTALL_*` env vars and calls `scripts/install.sh` to install brew/apt
     packages for the selected components, pre-warm the Neovim plugin cache, and
     create a convenience symlink `~/dotfiles -> ~/.local/share/chezmoi`.

When it finishes, open a new terminal. `zsh` should be your login shell
already; if not, `sudo chsh -s "$(command -v zsh)" "$USER"`.

To answer the prompts before applying, split the steps:

```sh
# macOS
command -v gum >/dev/null || brew install gum

# Debian Trixie
command -v gum >/dev/null || { sudo apt-get update && sudo apt-get install -y gum; }

chezmoi init crag-h4k      # clone + prompt for components
chezmoi apply              # write only the selected components
```

## Choosing components

With [`gum`](https://github.com/charmbracelet/gum) installed, `chezmoi init` shows a
checkbox TUI: space toggles a component, enter confirms, esc cancels. On re-runs
the header hints the current selection. `gum` is installed as part of the macOS base
toolchain and Debian base package set on first apply (and is included in the
bootstrap step above), so it is
available from the second `chezmoi init` onward (see
[Changing components later](#changing-components-later)).

Without `gum` - if you skipped the bootstrap install - it falls back to a
typed numbered menu:

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

Both paths resolve to the same `componentSelection` string and the same
`[data.components]` tables. For the typed menu:

- Numbers: any subset (e.g. `1 3` for zsh + neovim). Spacing and order do not
  matter - `1 3`, `13`, and `3 1` are equivalent.
- Enter: the default, `1 2 3 4` (zsh + tmux + neovim + git; no AI tools).
- `all`: the default set (`1 2 3 4`).
- `all+`: everything, adding the AI tools and the `terminal` component. Like the
  other submenus, `all+` takes each parent at its default sub-features only, so
  `terminal` comes on with `ghostty` (its default) but not `iterm2`; add `iterm2`
  by selecting it in the submenu.

The component list is the single source of truth in `.chezmoi.toml.tmpl`; the gum
options and the typed menu are both generated from it, so adding a component is a
one-line edit there. Set `DOTFILES_NO_TUI=1` to force the typed menu even when gum
is installed.

### Sub-feature submenus (git, ai, terminal)

`git`, `ai`, and `terminal` are not plain booleans - each opens a second checkbox
to pick its sub-features (so they are stored as the nested tables
`[data.components.git]`, `[data.components.ai]`, and `[data.components.terminal]`,
where "on" means any sub-feature is true):

- `git`: `config` (`~/.gitconfig`), `personal` (`~/.gitconfig.personal`),
  `ignore_global` (`~/.gitignore_global`). `git` is in the default set, but the
  submenu pre-selects only `ignore_global` - so by default you get
  `~/.gitignore_global` and not `~/.gitconfig` (identical to the old behavior).
- `ai`: `claude_hooks` (merges the Claude notify hooks into `~/.claude/settings.json`),
  `codex_hooks` (merges the Codex notify hook + `tui.notifications` into
  `~/.codex/config.toml`), `statusline` (reserved placeholder, gates nothing yet),
  `codecompanion` (CodeCompanion.nvim + the `claude-agent-acp` bridge). `codecompanion`
  is listed last because it is the heaviest sub-feature - it pulls in node, npm, and
  the npm-installed bridge. `ai` stays off by default; if picked, the submenu still
  defaults to `codecompanion`.
- `terminal`: `ghostty` (Ghostty config + quick-terminal dropdown, macOS and Linux)
  and `iterm2` (iTerm2 Dynamic Profiles, macOS only). `terminal` stays off by
  default; if picked, the submenu defaults to `ghostty`. `iterm2` carries an `os`
  tag, so the submenu hides it on non-macOS (the data key is still emitted for
  column parity, and the file gate in `.chezmoiignore` also enforces darwin).

With `gum` the submenu is a nested checkbox seeded with your current/default
sub-features; without it (or under `DOTFILES_NO_TUI`) it falls back to a typed
sub-menu, and Enter / no-tty takes the defaults. The submenu only appears when its
parent component is selected.

`ai` keeps AI tooling opt-in, so nothing AI-related installs unless you ask for it.
`codecompanion` ships buffer contents to an LLM, so a sentinel file
(`~/.config/nvim/.codecompanion-enabled`) gates the plugin at startup; you can
`touch`/`rm` it to flip per-host without re-running `init`. The `claude-agent-acp`
bridge is installed via npm into `~/.local/bin`, and the chat reuses your existing
`claude` login (no token to store). `codecompanion` without `neovim` is a no-op.

A component (or sub-feature) that is off is excluded two ways: its target files
are added to `.chezmoiignore` so `chezmoi apply` never writes them, and its plugin
externals are dropped from `.chezmoiexternal.toml` so they are never fetched.
`~/.gitignore_global` follows the `git > ignore_global` sub-feature (on by
default), `~/.claude/settings.json` follows `ai > claude_hooks` (off by default),
`~/.codex/config.toml` follows `ai > codex_hooks` (off by default),
`~/.config/ghostty` follows `terminal > ghostty` (on when `terminal` is picked),
and `~/.config/iterm2` follows `terminal > iterm2` and `darwin` (macOS only). The
base
files install regardless of selection: `~/.tfswitch.toml` and
the tool linter configs (`~/.darglint`, `~/.flake8`, `~/.tflint.hcl`,
`~/.markdownlint.yaml`, `~/.config/yamllint/config`). Those linter configs are
plain tool configs, not neovim's, so they live at each tool's own path and
install even without the neovim component.

The raw answer is stored as `componentSelection` and parsed into
`[data.components]` booleans in `~/.config/chezmoi/chezmoi.toml`, reused on every
subsequent `chezmoi apply` without re-prompting.

### terminal (ghostty, iterm2)

`terminal` is opt-in (not in the default set) and carries terminal-emulator config
as two sub-features: `ghostty` (cross-platform, the submenu default) and `iterm2`
(macOS only). Both are gated at the file layer in `.chezmoiignore`; `iterm2` also
gates on `.chezmoi.os == "darwin"` and its cask install runs only in the macOS arm
of `scripts/install.sh`, so selecting `iterm2` on Debian is a harmless no-op.

#### ghostty

Ghostty runs on macOS and Linux. Its config lives at `~/.config/ghostty/config`,
templated from `dot_config/ghostty/config.tmpl` so the macOS-only keys and the
global-shortcut modifier are gated per OS. The palette is the single source of
color truth in `~/.config/ghostty/themes/gud-theme.conf` - a Dracula-family "gud"
variant that matches the tmux status line and the nvim `dracula` colorscheme, so
the whole terminal reads as one theme. The font is Hack Nerd Font Mono, so the
prompt and tmux status-line glyphs render. A Yakuake-style quick-terminal dropdown
(position top, size 40%, autohide) toggles from a global shortcut:
`global:cmd+grave_accent=toggle_quick_terminal` on macOS (needs Accessibility
permission), and `global:ctrl+grave_accent=toggle_quick_terminal` on Linux (needs
a desktop that implements the XDG GlobalShortcuts portal).

On macOS, Ghostty also reads a config-shadow at `~/Library/Application
Support/com.mitchellh.ghostty/config`. The dotfiles manage only the XDG path
(`~/.config/ghostty`); if that Application Support path exists (for example a
leftover symlink from an older setup), remove it so it cannot override this config.

Selecting `ghostty` installs the binary as well as the config, gated by
`INSTALL_TERMINAL_GHOSTTY` (dug from `terminal.ghostty`). On macOS `chezmoi apply`
installs the Homebrew cask (`brew install --cask ghostty`), guarded to skip if
`/Applications/Ghostty.app` already exists or the cask is already present. On
Debian it installs the config only and does not fetch the binary: Ghostty has no
official Debian apt package (the project ships source builds plus community repos;
Ubuntu 26.04+ has it, Debian does not), and this profile is a headless trixie
container where a GUI terminal is not provisioned. To install Ghostty on a real
Linux desktop, use the Ghostty Linux docs (<https://ghostty.org/docs/linux>) or a
community Debian repo such as <https://debian.griffo.io>, then let the managed
config apply on top.

#### iterm2

Profiles are managed as iTerm2 **Dynamic Profiles** (JSON), not a full prefs
plist. The JSON is kept at a clean, chezmoi-managed path,
`~/.config/iterm2/dotfiles.json`, and `scripts/install-iterm2.sh` symlinks it into
the one directory iTerm2 reads dynamic profiles from
(`~/Library/Application Support/iTerm2/DynamicProfiles/`) - so the repo carries no
`~/Library` tree. iTerm2 loads dynamic profiles non-destructively, with no
prefs-folder redirect and no machine-state cruft (window frames, last-directory
bookmarks, updater timestamps) in the repo. Dynamic profiles are read-only in the
iTerm2 UI; edit the JSON to change them.

On a fresh machine the profiles load straight from the JSON. On a machine that
already had them as regular profiles, iTerm2 keeps the regular copies (it rejects
a dynamic profile whose Guid matches an existing one, and will not run with an
empty profile list); the committed JSON still serves as source of truth and a
clean, diffable snapshot.

When selected on a Mac, `chezmoi apply` installs the iTerm2 cask
(`brew install --cask iterm2`) and writes the JSON, then `scripts/install-iterm2.sh`
creates the symlink, pins the default-profile Guid, and sets a few app-level
behavior toggles via `defaults write`. Restart iTerm2 to pick up the global
`defaults` (a running iTerm2 rewrites its prefs on quit). The AI API key lives in
the macOS Keychain and is intentionally not synced.

To regenerate the committed profiles from your current iTerm2 profiles (re-scrub
any machine-specific fields such as `Working Directory` afterward):

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

> One-time migration: if your `~/.config/chezmoi/chezmoi.toml` predates the
> `git`/`ai` submenus (it has flat `gitconfig`/`ai` booleans under
> `[data.components]`), run `chezmoi init` once before the next `apply` to
> regenerate the config with the nested `[data.components.git]` /
> `[data.components.ai]` tables. The templates `dig` into those tables, so an
> `apply` against a stale flat config errors until the schema is regenerated.
>
> The same applies to the `terminal` component: if your config still has the old
> bare `iterm2` boolean under `[data.components]` (from before `iterm2` became the
> `terminal > iterm2` sub-feature), run `chezmoi init` once to regenerate the
> `[data.components.terminal]` table. To keep iTerm2 selected through the
> migration, pick `terminal` with both `ghostty` and `iterm2` in the submenu (a
> plain re-init defaults `terminal` to `ghostty` only). Digging `terminal.iterm2`
> against the stale bare `iterm2` key does not error (it just reads the default),
> but the file gates track `terminal.*`, so `iterm2` config is unmanaged until the
> table is regenerated.

Two ways:

- Re-open the picker. The `ccomp` alias runs `chezmoi init --apply`:

  ```sh
  ccomp     # alias for: chezmoi init --apply
  ```

  With `gum` installed (it is, after the first macOS apply) this re-opens the gum
  TUI with the current selection hinted, then applies. The gum picker is not
  gated by `promptStringOnce`, so it re-prompts every time - no need to clear
  `componentSelection` first. Cancelling the picker (Esc) keeps the current
  selection unchanged.

  Without `gum`, `chezmoi init` falls back to `promptStringOnce`, which will not
  re-prompt while `componentSelection` is set; clear it first, then re-init:

  ```sh
  sed -i.bak '/componentSelection/d' ~/.config/chezmoi/chezmoi.toml
  chezmoi init --apply
  ```

- Or edit `~/.config/chezmoi/chezmoi.toml` directly and adjust the booleans,
  then `chezmoi apply`:

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
  `[data.components.ai]`, and `[data.components.terminal]` tables - once a TOML
  sub-table is opened, later bare keys fall into it.

Turning a component off removes its files on the next apply (its targets are now
ignored); turning one on writes them and fetches its plugins. Unmodified managed
files are removed cleanly. A file you edited locally is left in place rather than
deleted, so back it up first if you want it gone.

Enabling a component that installs packages (e.g. `ai`) also re-runs the
installer automatically: `run_once_after_00-install.sh` embeds the component
booleans, so flipping one changes the script's rendered content and chezmoi
re-runs it on the next apply, installing the newly selected tools. If it does not
re-run for some reason, force it:

```sh
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply
```

So to enable the AI tools after the fact: set `codecompanion = true` under
`[data.components.ai]` in `~/.config/chezmoi/chezmoi.toml` (or re-run the menu,
include `5`, and check `codecompanion` in the submenu), then `chezmoi apply`.
That installs the Claude Code ACP bridge and provisions the CodeCompanion
sentinel - no full reinstall needed.

## How it works

- **Content I author** (configs, custom functions, install scripts, docs)
  lives in this repo as regular files following chezmoi naming conventions
  (`dot_zshrc` -> `~/.zshrc`, `dot_zsh/aliases` -> `~/.zsh/aliases`, etc.).
- **Component selection** is a chezmoi-native concern. `.chezmoi.toml.tmpl`
  prompts at `chezmoi init` - a `gum` checkbox TUI when gum is on `PATH`,
  else a typed `promptStringOnce` numbered menu - parses the answer, and writes
  `[data.components]` (plus the nested `.git` / `.ai` sub-feature tables) into the
  per-host config. The `git` and `ai` components each open a second submenu for
  their sub-features. Both the gum options and the typed menu are generated from
  one `$components` list (with `$gitFeatures` / `$aiFeatures`) in that file.
  `.chezmoiignore` and `.chezmoiexternal.toml` are both templated off
  `.components.*` (down to `dig`-ing the sub-feature tables): an off component or
  sub-feature has its targets ignored and its externals skipped.
- **Upstream plugins** are chezmoi externals (`.chezmoiexternal.toml`), fetched
  and refreshed by `chezmoi apply` on a weekly `refreshPeriod`. Only the
  selected components' externals are declared.
- **System packages** (zsh, neovim, tmux, fzf, gh, zoxide, gum, yq, etc.) are installed
  by `scripts/install.sh` on first apply. The small base toolchain (`git`,
  `make`, `curl`, `gum`, etc.) installs first; packages for selected components
  are then deduped and batched into one `brew install` / `apt-get install -y`
  call per OS.
  `run_once_after_00-install.sh` drives `install.sh` with the component selection
  passed as `INSTALL_*` env vars.
- **Status-bar network indicator.** The `↓ • ↑` throughput in the tmux status bar
  comes from the `xamut/tmux-network-bandwidth` plugin (cross-platform, replaces the
  Linux-only `tmux-net-speed`). It needs `coreutils`+`gawk` on macOS and
  `gawk`+`net-tools` on Debian; those ride along in the tmux package set. It sums all
  interfaces, so VPN and VM-bridge traffic are included in the number.

## What lives where

| Path in repo | Target on host | Notes |
|---|---|---|
| `dot_zshrc` | `~/.zshrc` | real file |
| `dot_zshenv` | `~/.zshenv` | real file |
| `dot_zsh/aliases` | `~/.zsh/aliases` | real file |
| `dot_zsh/bin/executable_*` | `~/.zsh/bin/*` | exec bit preserved |
| `dot_zsh/custom/functions/*.zsh` | `~/.zsh/custom/functions/*.zsh` | |
| `dot_zsh/custom/themes/gud.zsh-theme` | `~/.zsh/custom/themes/gud.zsh-theme` | custom oh-my-zsh theme; `ZSH_THEME="gud"` |
| `dot_tmux.conf` | `~/.tmux.conf` | real file; sources `notify.conf` (notify config moved to `notify.yaml`) |
| `dot_tmux/conf.d/*.conf` | `~/.tmux/conf.d/*.conf` | incl. `notify.conf` (status-bar flag + focus-clear) |
| `dot_config/notify/sounds/*.mp3` | `~/.config/notify/sounds/*.mp3` | notification audio files |
| `dot_config/notify/notify.yaml` | `~/.config/notify/notify.yaml` | single notify config: palette, groups, sounds, volume, thresholds, binary map; gated on `zsh`/`tmux` |
| `dot_config/notify/lib.sh` | `~/.config/notify/lib.sh` | shared `notify_fire`/`notify_clear`/`notify_play` + yq reader (array-free POSIX) |
| `dot_claude/hooks/notify-tmux.sh` | `~/.claude/hooks/notify-tmux.sh` | Claude `Stop`/`Notification`/`PreToolUse:AskUserQuestion` hook; gated on `ai > claude_hooks` |
| `dot_claude/hooks/notify-clear.sh` | `~/.claude/hooks/notify-clear.sh` | Claude `UserPromptSubmit` hook (clears); gated on `ai > claude_hooks` |
| `dot_claude/modify_settings.json` | `~/.claude/settings.json` (merge) | chezmoi `modify_` script: injects the notify hooks, preserves your other settings; gated on `ai > claude_hooks` |
| `dot_codex/hooks/notify-tmux.sh` | `~/.codex/hooks/notify-tmux.sh` | Codex `agent-turn-complete` notify hook (color+sound); gated on `ai > codex_hooks` |
| `dot_codex/modify_private_config.toml` | `~/.codex/config.toml` (merge) | chezmoi `modify_` script: injects `notify` + `tui.notifications`, preserves Codex's `[projects.*]`/`[tui.*]` tables, keeps mode 600; gated on `ai > codex_hooks` |
| `dot_config/nvim/init.lua` | `~/.config/nvim/init.lua` | lazy.nvim entrypoint |
| `dot_config/nvim/lua/statusline.lua` | `~/.config/nvim/lua/statusline.lua` | |
| **Linter configs (base, each at its own path)** | | |
| `dot_darglint` | `~/.darglint` | docstring style |
| `dot_flake8` | `~/.flake8` | python style; `flake8` alias appends it |
| `dot_tflint.hcl` | `~/.tflint.hcl` | terraform lint rules |
| `dot_markdownlint.yaml` | `~/.markdownlint.yaml` | markdown rules; nvim-lint points `--config` here |
| `dot_config/yamllint/config` | `~/.config/yamllint/config` | yamllint's XDG config path |
| **System-level tool configs** | | |
| `dot_tfswitch.toml` | `~/.tfswitch.toml` | terraform version switcher |
| `gitconfig.example` | reference only | seed for `~/.gitconfig`; install.sh prompts to copy when `git > config` is on |
| `gitconfig.personal.example` | reference only | seed for `~/.gitconfig.personal`; copied when `git > personal` is on |
| `dot_gitignore_global` | `~/.gitignore_global` | global ignore patterns; gated on `git > ignore_global` (on by default) |
| `.chezmoi.toml.tmpl` | `~/.config/chezmoi/chezmoi.toml` | prompts for components at init; stores `[data.components]` + nested `.git` / `.ai` sub-feature tables |
| `.chezmoiignore` | (templated) | ignores an off component's (or sub-feature's) target paths |
| `.chezmoiexternal.toml` | (templated externals) | plugins gated by `.components.zsh` / `.components.tmux` |

## Notifications

Terminal-native attention cues when a long process finishes or Claude/Codex needs you. Visual cue always; sound optional per group (empty sound = silent). No notification-center popups.

- **Config (one file).** Everything - the color palette, per-group `bg`/`accent`/`sound`, default and per-group `volume`/`threshold`, the binary-to-group map, the ignore-list, and debug logging - lives in `~/.config/notify/notify.yaml`, read via [`yq`](https://github.com/mikefarah/yq) (mikefarah, v4). `groups` are triggered by a finished command's binary; `integrations` (claude/codex) are triggered by an event hook and are auto-added to the ignore-list (so launching the CLI never fires the command path). Palette names resolve to hex; a raw `#hex` or `default` passes through. Edit the YAML (new shells re-read it; `tmux source-file ~/.tmux.conf` reloads the renderer).
- **Shared logic.** `~/.config/notify/lib.sh` (array-free POSIX, sourced by both the zsh notifier and the bash hooks) reads the config and does the recolor + sound. It resolves a mikefarah `yq` even under a stripped PATH (preferring `~/.local/bin/yq`, ignoring a stray apt/kislyuk `yq`) and locates tmux the same way, bypassing the oh-my-zsh tmux wrapper.
- **Rendering.** `~/.tmux/conf.d/notify.conf` renders the status-bar flag (per-group accent) and pane tint, and clears them when you return focus to the pane. tmux is the only surface that draws; outside tmux the system is inert by design.
- **Detection.** `~/.zsh/custom/functions/notify-process.zsh` builds its binary-to-group map, per-group thresholds, and ignore-list once at shell init (a single `yq` call), then `preexec`/`precmd` flag the pane when a named binary (terraform, brew, ...) finishes at/above its group's threshold, or any command runs past the catch-all `default` threshold. A nonzero exit uses the `error` group.
- **AI attention.** The Claude Code `Stop`, `Notification`, and `PreToolUse:AskUserQuestion` events call `notify-tmux.sh`, registered in `~/.claude/settings.json` via the `modify_` script (`dot_claude/modify_settings.json`) that merges the hooks on each `chezmoi apply` without clobbering model/effort/plugins. Matcher-less `Notification` covers permission prompts and idle; `PreToolUse:AskUserQuestion` covers the question tool (which emits no `Notification` event). `~/.claude/settings.local.json` is never loaded and `.claude` settings do not merge up the directory tree; the corporate-managed `~/.claude.json` is left untouched. A fresh `claude` session picks up the hooks. Codex is wired the same way via `~/.codex/config.toml` (the `modify_private_config.toml` merge, gated on `ai > codex_hooks`): its external `notify` program calls `notify-tmux.sh` on `agent-turn-complete` (the color+sound "your turn" flag). Codex never sends the notify program an approval event, so `notify` cannot cover permission prompts; the merge also sets `tui.notifications` (`approval-requested`), Codex's own alert, which is a no-op under tmux today ([openai/codex#16855](https://github.com/openai/codex/issues/16855)) and activates once that lands. A restart of `codex` picks up the config.
- **Debug.** Off by default. Set `settings.debug: true` (or `export NOTIFY_DEBUG=1`) to trace fires to `settings.log` (default `~/.config/notify/notify.log`); the log self-caps at ~1 MB.
- **yq dependency.** Installed with the `zsh` or `tmux` component: `brew install yq` on macOS, the mikefarah binary fetched to `~/.local/bin` on Debian. Do **not** `apt install yq` on Debian - that is a different (python/kislyuk) tool with incompatible syntax, which the system detects and ignores.

### Standalone install (no chezmoi)

To install only the notify subsystem on a machine that does not use the full chezmoi dotfiles, run the standalone installer from a checkout of this repo:

```sh
scripts/install-notify.sh          # --force to overwrite an existing notify.yaml
```

It copies the same files into `~/.config/notify/` (including `sounds/`), `~/.tmux/conf.d/`, and `~/.claude/hooks/`, installs mikefarah `yq` (brew on macOS, binary to `~/.local/bin` on Debian), and wires `~/.zshrc`, `~/.tmux.conf`, and `~/.claude/settings.json`. When the `codex` CLI is present it also installs `~/.codex/hooks/notify-tmux.sh` and merges `notify` + `tui.notifications` into `~/.codex/config.toml` (mode 600 preserved). It is idempotent. If you use `chezmoi apply`, notify is already installed - do **not** also run this (the zsh notifier would load twice); the script refuses unless you pass `--force`. This is the same layout the beholder coworker package installs.

Manual equivalent, if you prefer not to run the script:

1. `mkdir -p ~/.config/notify/sounds ~/.tmux/conf.d ~/.claude/hooks`
2. Copy `dot_config/notify/notify.yaml`, `dot_config/notify/lib.sh`, and `dot_config/notify/sounds/*.mp3` to `~/.config/notify/` (sounds go in `~/.config/notify/sounds/`); `dot_zsh/custom/functions/notify-process.zsh` to `~/.config/notify/notify-process.zsh`; `dot_tmux/conf.d/notify.conf` to `~/.tmux/conf.d/`; and `dot_claude/hooks/executable_notify-tmux.sh` / `executable_notify-clear.sh` to `~/.claude/hooks/notify-tmux.sh` / `notify-clear.sh` (then `chmod +x` both).
3. Install mikefarah `yq`: `brew install yq` (macOS) or fetch the `yq_linux_<arch>` binary to `~/.local/bin` (Debian; do **not** `apt install yq` - that is a different tool).
4. Add to `~/.zshrc`: `[ -f ~/.config/notify/notify-process.zsh ] && source ~/.config/notify/notify-process.zsh`
5. Add to `~/.tmux.conf`: `source-file ~/.tmux/conf.d/notify.conf` (this overrides `window-status-format` / `pane-border-format` - reconcile with your status bar).
6. Register the Claude hooks: `python3 dot_claude/modify_settings.json < ~/.claude/settings.json > /tmp/s && mv /tmp/s ~/.claude/settings.json` (the merge preserves your existing settings).
7. Reload: `tmux source-file ~/.tmux.conf`, open a new shell, restart Claude Code.

## Daily operation

```sh
# Edit a config file via chezmoi (so the source tree stays the source of truth):
chezmoi edit ~/.zshrc
chezmoi apply                      # materialize the edit into $HOME

# Or edit the source tree directly and then apply (~/dotfiles is a symlink to
# ~/.local/share/chezmoi, created by scripts/install.sh):
cd ~/dotfiles
$EDITOR dot_zshrc
chezmoi apply

# Pull upstream plugins now instead of waiting for weekly refresh:
chezmoi apply --refresh-externals

# Re-run the install scripts (e.g. after updating packages):
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply

# Inspect what chezmoi thinks should change:
chezmoi diff

# Sync chezmoi source with this repo's origin:
chezmoi update                     # git pull in source + apply
```

## Supported platforms

- macOS (Homebrew)
- Debian / Ubuntu (`apt-get`, with sudo)

Other Linux distros work if you install the listed binaries yourself; the
config is distro-agnostic.

## Uninstall

```sh
chezmoi purge          # removes chezmoi source and state
rm -rf ~/.zsh ~/.tmux ~/.config/nvim ~/.config/yamllint ~/.local/share/nvim-venv
rm -f ~/.zshrc ~/.zshenv ~/.tmux.conf
rm -f ~/.darglint ~/.flake8 ~/.tflint.hcl ~/.markdownlint.yaml
rm -f ~/.gitignore_global ~/.tfswitch.toml
rm -f ~/dotfiles    # convenience symlink created by install.sh
```
