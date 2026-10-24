<!-- docs/operation.md -->
# Operation

## Table of Contents

- [Daily operation](#daily-operation)
- [Lazygit](#lazygit)
- [Telemetry opt-outs](#telemetry-opt-outs)
- [Telemetry opt-outs](#telemetry-opt-outs)
- [OpenCode updates](#opencode-updates)
- [Worktree and agent directories](#worktree-and-agent-directories)
- [Local overrides](#local-overrides)
  - [Shell PATH additions](#shell-path-additions)
  - [OpenCode terminal settings](#opencode-terminal-settings)
  - [OpenCode prompt submit keys](#opencode-prompt-submit-keys)
  - [OpenCode idle locations](#opencode-idle-locations)
  - [OpenCode server plugins](#opencode-server-plugins)
- [Terminal (tmux) behavior](#terminal-tmux-behavior)
  - [Status bar](#status-bar)
- [Statusline (Claude / Codex)](#statusline-claude--codex)
- [OpenViking memory](#openviking-memory)
- [SSH MCP for OpenCode V2](#ssh-mcp-for-opencode-v2)
- [Caveman compression](#caveman-compression)
- [Secret scanning](#secret-scanning)
- [Docker and Terraform checks](#docker-and-terraform-checks)
- [Supported platforms](#supported-platforms)
- [Uninstall](#uninstall)

## Daily operation

```sh
# Edit the source and apply it in one command:
chezmoi edit --apply ~/.zshrc

# Or edit the source tree directly and then apply (~/dotfiles is a symlink to
# ~/.local/share/chezmoi, created by scripts/install.sh):
cd ~/dotfiles
$EDITOR home/dot_zshrc
chezmoi apply

# Refresh selected chezmoi externals, then check the complete selected package set:
chezmoi apply --refresh-externals

# Open only the package plan and installation-mode prompt:
cup

# Run unattended package checks using the saved package mode:
DOTFILES_ASSUME_YES=1 chezmoi apply

# Inspect what chezmoi thinks should change:
chezmoi diff

# Read the latest installer log without running package work:
bash ~/dotfiles/scripts/install.sh --log

# Print the log filename for copying or searching:
bash ~/dotfiles/scripts/install.sh --log-path

# Sync chezmoi source with this repo's origin:
chezmoi update                     # git pull in source + apply
```

From a feature worktree, point chezmoi at that checkout explicitly:

```sh
cd /path/to/dotfiles-worktree
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

The repository-level `.chezmoiroot` still directs chezmoi into `home/`. It is
safe to review a worktree this way without replacing your normal source
directory.

With `installMode = "packages"`, every apply refreshes the selected package
plan, prompts for pending changes, and skips current packages. This includes
`chezmoi update`, `chezmoi apply --refresh-externals`, and `chezmoi init --apply`.
It covers native packages, npm CLIs, release downloads, language tools, managed
Git checkouts, and Neovim packages. Source-controlled pins stay pinned; package
approval also initializes the palette submodule at the source's exact commit.

AI runtime installation uses three concurrent groups after prerequisites are
ready: isolated OpenCode, shared-prefix npm tools, and OpenViking. Install logs
prefix each line with the group name. A failed installer is counted while the
other groups finish; the overall package run still fails. Current and blocked
plan entries retain their existing skip and failure behavior.

Set `DOTFILES_RUNTIME_JOBS=1` for serial runtime installation, or `2` to limit
concurrency on a smaller host; the default is `3`. An OpenCode npm prefix that
resolves to the shared `~/.local` prefix forces serial execution. Interrupting
the runtime supervisor stops its active groups and their child processes.

Config-only mode skips package work. A headless apply without
`DOTFILES_ASSUME_YES=1` declines package changes. The direct chezmoi external
refresh flag can still refresh Git externals before the installer runs; omit it
to use the installer's cleanliness and fast-forward checks.

## Lazygit

Run `lazygit` in a repository to inspect file and hunk diffs, stage changes,
and browse commits. It is an interactive Git client: staging, commits, branch
changes and pushes in its UI modify the repository. Agent approval prompts do
not constrain actions you choose to take in Lazygit yourself.

The package planner includes Lazygit in the base Homebrew and Trixie APT sets,
independent of the Gum component selection. It installs only in approved package
mode. The managed `~/.config/lazygit/config.yml` renders from the selected
palette; macOS links its default config path to that same file. Its default
background Git fetch and branch forwarding are disabled so opening a repo
does not update remotes or other worktrees. Update checks, automatic conflict
staging, and force pushes are disabled as well. You can still fetch, stage,
commit, and push deliberately from the UI.

There is no official Oh My Zsh Lazygit plugin to enable. The existing `git`
plugin supplies shell aliases, but Lazygit does not need it. Run it in the
terminal attached to the machine with the checkout you want to review; a
local laptop terminal cannot display a checkout that only exists on a remote
host.

## Telemetry opt-outs

The managed `.zshenv` exports these settings in interactive, non-interactive,
and login Zsh sessions. Child processes inherit them, including commands called
through Oh My Zsh aliases and completions. Receiving a variable does not mean a
tool honors it.

| Export | Effect |
| --- | --- |
| `DO_NOT_TRACK=1` | Opts out in supporting tools, including current GitHub CLI telemetry. |
| `HOMEBREW_NO_ANALYTICS=1` | Disables Homebrew analytics without changing its persisted settings. |
| `CHECKPOINT_DISABLE=1` | Disables HashiCorp Checkpoint requests, including Terraform upgrade/security-bulletin checks and their anonymous signature. |

The tool-specific exports follow [Homebrew's analytics documentation][brew-analytics]
and [Terraform's Checkpoint documentation][terraform-checkpoint].
[GitHub CLI documents `DO_NOT_TRACK` support][gh-telemetry]; extensions and
Copilot CLI have separate policies. These settings do not block registry
downloads, provider/backend requests, or server-side logging of normal API use.

OpenViking's systemd unit and macOS LaunchAgent separately set `DO_NOT_TRACK=1`
because they run without a shell. That declares the preference; it does not
establish that every dependency honors it. GUI applications, unrelated services,
and container workloads do not automatically receive the shell exports.

### Oh My Zsh tool coverage

The configured plugins in `home/dot_zshrc` are the starting point for this audit:

| Plugin/tool | Coverage or remaining limitation |
| --- | --- |
| `brew`, `terraform`, `gh` | Covered by the exports above for the documented client-side behavior. |
| `aws` | Ordinary AWS CLI does not document a `DO_NOT_TRACK` opt-out in its [environment-variable reference][aws-env]. AWS SAM and CDK are different tools with separate telemetry controls; neither is selected by the `aws` plugin. |
| `docker`, `docker-compose` | The [Docker CLI][docker-env] and [Compose][compose-env] environment references do not document a universal telemetry opt-out. Docker Desktop has a separate setting described below. |
| `chezmoi`, `git`, `fzf`, `zoxide`, `tmux`, agent/completion/highlighting and display plugins | No additional telemetry opt-out was identified in the configured plugin implementations. This is not a guarantee about every executable, extension, or remote service they invoke. |

Oh My Zsh's [update checker][omz-updates] makes GitHub requests and does not test
`DO_NOT_TRACK`. Its existing update behavior is unchanged. Zsh history,
autosuggestions, directory history, and the managed history backups remain
local state; telemetry opt-outs do not disable them or erase their contents.

For Docker Desktop, turn off **Settings > General > Send usage statistics**.
[Docker documents this setting][docker-desktop] as controlling diagnostics,
crash reports, and usage data. The dotfiles do not manage Desktop's settings
store or impose a speculative Docker environment variable. Docker extensions
and cloud features may need their own review.

Go is installed by the Neovim component, rather than an Oh My Zsh plugin.
[Go's telemetry mode][go-telemetry] is a separate persisted setting: `local`
collects locally without uploading, while `off` stops collection too. This
change does not alter that setting.

[brew-analytics]: https://docs.brew.sh/Analytics
[terraform-checkpoint]: https://developer.hashicorp.com/terraform/cli/commands#upgrade-and-security-bulletin-checks
[gh-telemetry]: https://docs.github.com/en/github-cli/github-cli/github-cli-telemetry
[aws-env]: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-envvars.html
[docker-env]: https://docs.docker.com/reference/cli/docker/#environment-variables
[compose-env]: https://docs.docker.com/compose/how-tos/environment-variables/envvars/
[docker-desktop]: https://docs.docker.com/desktop/settings-and-maintenance/settings/#general
[omz-updates]: https://github.com/ohmyzsh/ohmyzsh/blob/master/tools/check_for_upgrade.sh
[go-telemetry]: https://go.dev/doc/telemetry

## OpenCode updates

OpenCode's `/update` command and `opencode2 update` use the isolated npm install
under `~/.local/share/opencode2`. The wrapper passes that prefix to npm and runs
OpenCode with `NPM_CONFIG_MIN_RELEASE_AGE=0`. The native updater requests an
exact new CLI version and platform package, a fresh SDK can require OpenTUI
packages published the same day, and plugin installs resolve moving tags, so a
release-age cooldown would reject exactly the releases an update is after.

Chezmoi-driven npm work bypasses your cooldown by design. The same variable is
exported by every npm entrypoint dotfiles drives:

- package-mode applies (`chezmoi apply`, `chezmoi update`, `cup`), including the
  package plan's inventory and candidate lookups;
- the npm installers for OpenCode, Copilot, SSH MCP, Caveman, and the Neovim
  npm tools, plus any Mason install the Neovim package step starts;
- runtime synchronization, which `opencode2` also runs at launch;
- the managed `opencode2` wrapper.

The value replaces an inherited one, so a shell that exports
`NPM_CONFIG_MIN_RELEASE_AGE=3` still gets `0` inside these processes. It exists
only in their process environment. Dotfiles never writes `~/.npmrc` or another
npm config file, and npm you run from a normal terminal keeps your policy.
Anything started by `opencode2` inherits the variable, including shell commands
an agent runs in a session. Run project installs that should honor the cooldown
outside it.

Runtime synchronization reads the installed CLI's SDK peer requirements and
OpenTUI Solid's declared dependencies and peers, then resolves compatible
OpenTUI and Solid.js candidates with `npm outdated`, which honors npm's date
filters. Installation consumes those exact versions. Missing peer metadata or
unresolved candidates stop the sync before npm changes the existing runtime;
there is no fallback to an unconstrained `latest` tag.

You can also update the CLI directly with npm:

```sh
npm install -g --prefix "$HOME/.local/share/opencode2" '@opencode/cli@latest'
```

Direct npm retains your npm configuration and may choose an older release when
a release-age window is set. Relaunch `opencode2` to synchronize its local SDK
with the installed CLI. Package-mode chezmoi applies update the same install
and synchronize the SDK in the same run.

When applying from another account's checkout, the installer can reuse the
palette submodule if its checkout matches the pinned commit and its tracked
files are present. Only the checkout owner can initialize or repair that
submodule. The verification uses command-scoped Git trust for the exact paths;
it does not add a global `safe.directory` exception or change source ownership.
Packages installed under `$HOME`, including Luacheck, belong to the account
running chezmoi.

## Worktree and agent directories

Two chezmoi data keys name the directories agents and humans share across
repositories. Both are settings, not fixed paths, so each host picks its own.

| Key | Default | First-init env seed | Holds | Created |
| --- | --- | --- | --- | --- |
| `worktreesDir` | `$HOME/worktrees` | `DOTFILES_WORKTREES_DIR` | Git worktrees, one flat directory per task: `<root>/<repo>-<slug>` | Every apply |
| `agentsDir` | `$HOME/agents` | `DOTFILES_AGENTS_DIR` | Local agent notes: plans, specs, drafts, memory, handoffs | Every apply with an `ai` sub-feature selected |

A value can be absolute, `~/...`, or `$HOME/...`. Relative paths, the
filesystem root, and characters outside letters, digits, spaces, and
`. _ @ % + = : , / ~ -` fail at init and apply rather than reaching a shell
export. Chezmoi stores the text you give it and expands it everywhere it is
used.

A saved value always wins. Re-running `chezmoi init` offers it back as the
pre-fill, even when the env var holds something else; the env var only seeds a
first init or an old config that lacks the key. An old config without the keys
applies with the defaults and needs no re-init.

The AI picker is where you change them. With AI tools selected, its page lists a
`directories` entry after the sub-features and shows the current paths in its
header, pre-filled the same way as below (saved value, else env seed, else
default):

```text
AI tools  (space toggles, enter confirms, esc cancels):
Worktrees:   ~/src/worktrees
Agent notes: $HOME/agents
> • claude_hooks - Claude settings.json notify hooks
  ...
  • directories - change the worktrees and agent-notes directories (unchecked keeps them)
```

The entry starts unchecked, is never a component, and is never saved: it is not in
`[data.components.ai]` or `aiSelection`, and the numbers of the other entries do
not move. Leave it unchecked and init asks nothing about directories; the values
stay as resolved. Check it (`x` toggles in Gum 2.x, which ignores Space; Tab works
too) and init opens exactly one more page, an editor holding both paths:

```text
Edit the paths: Enter saves, Ctrl+C keeps as shown
┃ worktrees: ~/src/worktrees
┃ agents: $HOME/agents
```

The editor opens on the saved value, else the env seed, else the default, so a
first init shows the default and every later init shows your last choice. Edit
either line, then press Enter. Keys
are case-insensitive, spaces around the colon are optional, blank lines are
ignored, and a line you delete or leave empty keeps its pre-filled value. Anything
you type is stored as written, in whichever of the three forms you use. Ctrl+C,
Escape (Gum 2.x), or an empty answer keeps what is shown, with no second prompt.

| Situation | Behavior |
| --- | --- |
| Gum installed, terminal available | `directories` on the AI page; checked, it opens one `gum write` editor |
| No Gum, terminal available | `10) directories` in the typed AI menu; chosen, it asks each path with chezmoi's `promptString`, pre-filled, Enter keeps it |
| `DOTFILES_NO_TUI` set | No entry, no prompt; the pre-fill is used |
| No usable terminal (stdin is not a TTY, or `/dev/tty` will not open) | No entry, no prompt; the pre-fill is used |
| `cup` (`DOTFILES_PACKAGE_UPDATE`) or the retired `all+` migration | No entry, no prompt; the pre-fill is used |
| AI tools not selected | The AI page is not shown; the saved value or default stands |

The gate follows the palette picker's rules, not the submenus': chezmoi's typed
prompt fails outright with no terminal, so an entry that could not ask is not
offered. `chezmoi apply` never prompts. `chezmoi init --apply` asks during its
init step only. The typed AI menu is asked once (`promptStringOnce`), so on a host
without Gum a re-init does not reopen it; change a value there by editing
`~/.config/chezmoi/chezmoi.toml` (below) or by clearing `aiSelection` first.

An answer that is not usable, or a line that is not `worktrees: <path>` or
`agents: <path>`, is explained and the editor reopens with your text kept, up to
three times; then init stops with the same error `apply` would give. A saved or
seeded value that is not usable shows as `(not usable)` in the page header and is
replaced by the default in the editor, so accepting it repairs the config. Leaving
the entry unchecked with such a value fails at the end of init, as `apply` would.

To pick a value on a new host, seed it once. Init takes the seed as is, or shows
it pre-filled if you check `directories` (add `DOTFILES_NO_TUI=1` to never be asked):

```sh
DOTFILES_WORKTREES_DIR=/opt/worktrees DOTFILES_AGENTS_DIR="$HOME/notes/agents" \
  chezmoi init --apply
```

To change it later, re-run `chezmoi init`, check `directories`, and edit the
pre-filled value, or edit `~/.config/chezmoi/chezmoi.toml` and apply:

```toml
[data]
    worktreesDir = "/opt/worktrees"
    agentsDir = "~/notes/agents"
```

The managed `~/.zshenv` renders both values as literal absolute paths and
exports them as `DOTFILES_WORKTREES_DIR` and `DOTFILES_AGENTS_DIR` in every zsh,
including non-interactive shells. The `git-worktree` and `handoff` skills read
those variables. Open a new shell (`exec zsh`) after changing a value. A
shell-only override belongs in `~/.zsh_private`; it changes what that shell
reports, not where dotfiles creates directories. Without the `zsh` component
`~/.zshenv` is not managed, so the variables are not exported; the skills then
use `$HOME/worktrees` when it exists and ask for a handoff root.

Apply creates a missing directory with mode 755 and leaves an existing one
untouched: its mode, owner, and contents stay as they are. Dotfiles never runs
`sudo`. When the nearest existing parent is not writable, for example
`/opt/worktrees` on a fresh host, apply keeps going and prints the one-time
command for you to run:

```sh
sudo install -d -o "$USER" -m 0755 /opt/worktrees
```

Existing worktrees and notes are not moved. Move a worktree with
`git worktree move <path> <new-path>` from its repository.

## Local overrides

Each managed tool reads one unmanaged file where you can change its behavior
without editing the config in this repo. Adopt these dotfiles, drop your
settings in these files, and `chezmoi update` keeps working:

- Ghostty: `~/.config/ghostty/override.conf`
- tmux: `~/.tmux/conf.d/override.conf`
- Zsh: `~/.zsh_override`
- Neovim: `~/.config/nvim/lua/override.lua`
- Git: `~/.gitconfig.override`
- OpenCode CLI settings: `~/.config/opencode/cli.override.json`
- OpenCode launch behavior: `~/.config/opencode/override.zsh`

With `ai > opencode` selected, chezmoi also merges portable preferences into
`~/.config/opencode/AGENTS.md`: use the `question` tool for decisions and Git
write approvals, and use `rg` instead of `grep` for shell searches, including
SSH commands and pipeline filters. Dedicated search tools remain preferred.
Selecting OpenViking adds find-before-local-loaders guidance; see
[OpenViking memory](openviking.md#review-and-clean-up-memories).
Existing local instructions stay intact. These are agent instructions, not
shell aliases or a change to third-party scripts. A normal apply updates them;
source edits alone do not change an already installed configuration.
Its OpenCode config merge adds Plan handoff access for three roots without
replacing unrelated local Plan rules: `~/.local/share/agent-handoffs`,
`/opt/ai/handoffs`, and `<agentsDir>/plans`, where `<agentsDir>` is the resolved
`data.agentsDir` (default `$HOME/agents`) written as a literal absolute path. The
managed block follows `agentsDir` on the next apply after you change it. Any
other root still needs a private permission overlay.

None are chezmoi-managed. Each is listed
unconditionally in `home/.chezmoiignore`, so chezmoi never applies or removes
them, and `chezmoi add` and `chezmoi re-add` refuse them. Your settings stay
yours and never reach this public repo. The installer creates an empty mode-600
Git override only when managed Git config is selected and the file is absent.

Every include is optional. Ghostty
uses the `?` path prefix, tmux uses `source-file -q`, Git silently skips a
missing include, Zsh uses an `[[ -r ]]` guard, and Neovim uses a guarded
`pcall`. Delete a file and the tool starts clean.

Each override loads after its managed base. Most load at the absolute end. tmux
loads its override before the managed plugin list and the final TPM command so
local plugin declarations and options exist before plugin startup.

The OpenCode wrapper passes `cli.override.json` to the native
`OPENCODE_CLI_CONFIG_CONTENT` loader. An explicitly exported value takes
precedence over the file. Use this local JSON file for terminal preferences
and extra CLI plugins. Keep private plugins under
`~/.config/opencode/v2-plugins/local/`, which is also ignored by chezmoi.
Ordinary preferences belong in `cli.json` through **Open settings**; see
[OpenCode terminal settings](#opencode-terminal-settings) for what chezmoi
keeps and what it resets.

The wrapper sources `override.zsh` after resolving its isolated `binary` and
classifying `interactive` and `explicit_server`, before choosing standalone
mode. The override can export environment variables or execute `"$binary"`
with local server arguments. Credentials can be sourced from the ignored
`~/.config/opencode/remote.env`; keep them out of the public source tree.
A failed override stops the launch.

```text
# ~/.config/ghostty/override.conf
font-size = 14
```

```zsh
# ~/.zsh_override
alias ll='eza -l'
export EDITOR=vim
```

### Shell PATH additions

An external installer can append a `~/.local/bin` PATH guard to `.zshrc`, causing
chezmoi to report a local edit. The managed `.zshenv` already adds that directory.
Before apply, the backup hook removes only the recognized duplicate tail when
the rest of `.zshrc` exactly matches managed source and the installed `.zshenv`
still exports that PATH entry on its own line. (`.zshenv` is a template, so its
rendered bytes are not compared.) The full original remains in the uniquely
named pre-apply snapshot.

Other local edits, symlinked targets, and a `.zshenv` without that export are left alone.
They keep the normal conflict prompt. Put intentional shell customizations in
`~/.zsh_override`; do not use “overwrite all” to dismiss an unexplained change.

### Git identities

The managed Git config contains no name, email, signing key, or private path.
It sets `user.useConfigOnly = true` and includes `~/.gitconfig.override` last.

Git cannot nest `[user]` values under `includeIf`; conditional includes can only
name another file. To keep one private file, define aliases that write identity
settings into the current repository's local `.git/config`:

```gitconfig
# ~/.gitconfig.override
[alias]
    identity-personal = "!f() { git config --local user.name 'Personal Name'; git config --local user.email 'personal@example.invalid'; }; f"
    identity-work = "!f() { git config --local user.name 'Work Name'; git config --local user.email 'work@example.invalid'; }; f"
```

Run `git identity-personal` or `git identity-work` once after cloning. Add local
`user.signingKey`, `gpg.format`, and `commit.gpgSign` commands to either alias if
that identity signs commits.

The former `~/.config/git/override.conf` is no longer loaded. Migrate any useful
settings into `~/.gitconfig.override`; the old file remains ignored and is not
deleted automatically.

### tmux plugins

Disable default plugins independently by setting their switches to `off`:

```tmux
# ~/.tmux/conf.d/override.conf
set -g @dotfiles_plugin_tmux_cpu off
set -g @dotfiles_plugin_tmux_network_bandwidth off
```

All five switches default to `on`:

| Switch | Default plugin |
| --- | --- |
| `@dotfiles_plugin_tmux_sensible` | `tmux-plugins/tmux-sensible` |
| `@dotfiles_plugin_tmux_yank` | `tmux-plugins/tmux-yank` |
| `@dotfiles_plugin_tmux_cpu` | `tmux-plugins/tmux-cpu` |
| `@dotfiles_plugin_tmux_network_bandwidth` | `xamut/tmux-network-bandwidth` |
| `@dotfiles_plugin_tmux_resurrect` | `tmux-plugins/tmux-resurrect` |

TPM itself has no switch because it initializes the selected default plugins
and every local addition. Add a plugin with TPM's standard literal syntax. Put
its options before the declaration when the plugin reads them at startup:

```tmux
# ~/.tmux/conf.d/override.conf
set -g @continuum-restore 'on'
set -g @plugin 'tmux-plugins/tmux-continuum'
```

Reload tmux, then use `prefix + I` to install a local addition. TPM owns plugins
declared only in `override.conf`. Its package bindings are scoped accordingly:

| Binding | Scope |
| --- | --- |
| `prefix + I` | Install missing local plugins |
| `prefix + U` | Update one named local plugin, or every local plugin with `all` |
| `prefix + M-u` | Remove unused local plugin directories |

The wrapper refuses to update default names and protects every default checkout
during interactive TPM clean, including disabled plugins. Approved package mode
installs or fast-forwards TPM and the five default plugin repositories. Chezmoi
ignores the complete `~/.tmux/plugins` runtime tree and does not lock or track it.

TPM sees one combined plugin set during startup. Enabled defaults use
its runtime `@tpm_plugins` option, while local literal `@plugin` lines come from
TPM's static scan of sourced files. The final startup command then replaces the
package bindings with the local-only wrapper.

`@tpm_plugins` is deprecated upstream but remains supported. The managed config
rebuilds that option after `override.conf`, so do not set it yourself. Local
additions must use a one-line literal `set -g @plugin 'owner/repo'` declaration;
TPM does not discover a repository assembled through a variable or conditional.
Do not repeat a default repository as a local `@plugin`, or TPM can start it
twice.

TPM prefers `$XDG_CONFIG_HOME/tmux/tmux.conf` when that file exists. A separate
XDG main config can therefore hide this repository's `~/.tmux.conf` and its
sourced override from TPM's static scanner. Keep `~/.tmux.conf` as the active
main config when using this override path.

Disabling a plugin prevents it from starting in a fresh tmux server. Reloading
`~/.tmux.conf` in an existing server does not undo options, hooks, or bindings
that the plugin already installed. End the existing server and start a new one
for a disable to take full effect.

### OpenCode terminal settings

OpenCode V2 stores terminal settings in `~/.config/opencode/cli.json`, and
**Open settings** (`Ctrl+P`) writes to that file. Chezmoi merges into it through
`modify_private_cli.json.tmpl` instead of replacing it, so a settings change
survives `chezmoi init --apply` without a "changed since chezmoi last wrote it"
prompt. The target stays valid JSON with mode `0600`.

| Class | Keys | On every apply |
| --- | --- | --- |
| Enforced | `$schema`, `attention.notifications`, `attention.sound`, `keybinds.leader`, `leader.timeout`, the tab navigation keys (`session.tab.previous`, `session.tab.next`, `session.first`) with the pane and terminal defaults they displace (`pane.focus.left`, `pane.focus.right`, `terminal.select`, `terminal.close`, `terminal.toggle`), and the managed `plugins` entries at `@latest` | Reset to the managed value |
| Seeded | Theme, tabs, the other keybinds, session, animations, diffs, terminal, managed plugin `options` | Added only when that key is absent; an existing value is never changed |
| Migrated | The stock `session.sidebar.toggle` binding `<leader>b`, as a string or one-item list | Set to `none` to free Sidequest's panel toggle; custom bindings survive |
| Kept | Everything else | Untouched, including keys that newer OpenCode releases add |

The enforced keys protect integrations. `attention.notifications` and
`attention.sound` are OpenCode's own OS banners and sounds. The tmux notifier
tints the pane and window tab instead and deliberately raises no popups, so a
settings toggle that turned the native alerts on would double every signal. The
leader and its timeout are fixed at OpenCode's default `Ctrl+X`. The navigation
keys are fixed because every direction key must move between tabs and no two
managed actions may share a chord. OpenCode binds `<leader>` plus an arrow to
pane focus and the terminal pane, and `<leader>t` to the terminal toggle, which
collided with the session list on `<leader>t`, so those are released. A host
still on the old `Ctrl+G` leader moves to `Ctrl+X` on the next apply. The
`plugins` array turns off the stock footer
and configures the Pillbox and Sidequest terminal halves, the agent catalog,
attention tabs, and `/demo`.

Sidequest's `options.focusKey` is seeded to `<leader>p`, so `Ctrl+X`, then `P`
focuses its panel without taking over the leader. Change it in the Sidequest
entry's `options`; OC2's `keybinds` object does not accept plugin command IDs.
Keep the same Sidequest package reference in `opencode.jsonc` and
`cli.json` so OpenCode loads one terminal instance with the terminal options.

The attention-tabs entry is a local path in the object form,
`{"package": "./v2-plugins/attention-tabs", "options": {...}}`, and the merge
matches it by that path. Only two options are seeded: `sort` (`false`) and
`jumpKey` (`<leader>z`). The rest keep the plugin's own defaults, so a later
default reaches every host instead of being frozen by an earlier apply. To turn
tab sorting on, set `"sort": true` in that entry; later applies keep it. To turn
the plugin off, append `-dotfiles.attention-tabs` to `plugins`. The
[attention tabs section](components.md#opencode-attention-tabs) lists every
option.

`keybinds.agent.cycle` is seeded to `shift+tab` for the opening prompt. The
session-workflow plugin yields to that native binding before a session exists,
then handles Build → Plan → Auto cycling inside a session. An explicit custom
or disabled native binding survives apply, including one in `cli.override.json`.

Seeding is per key. A default added to the repository later reaches existing
hosts, and a value you changed is never touched. The cost is that a seeded key
you delete comes back on the next apply; set it to the value you want instead.
`tabs.enabled` is the legacy form of `tabs.mode` and loses to it, so the merge
does not seed `tabs.mode` next to an existing `tabs.enabled`.

The merge removes retired dotfiles entries, such as the old
`./v2-plugins/statusline` path, then appends any missing managed `plugins`
entry. It leaves your own entries, their order, and later `-id` controls alone.
An npm entry matches by package name whatever its version, so switching to `@latest`
rewrites `package` in place and keeps the entry's options, which are seeded per
key like the settings above. To turn off a managed plugin, append its control,
for example `-dotfiles.agent-catalog`.

`cli.override.json` is separate and wins at runtime. Nested objects merge over
`cli.json`, but arrays and scalars replace it, with two consequences:

| Override | Effect |
| --- | --- |
| `{"attention":{"notifications":true}}` | Turns native banners on for that host, even though chezmoi keeps `cli.json` at `false` |
| `{"plugins":["./v2-plugins/local/x"]}` | Replaces the whole array, removing the managed footer/Sidequest options, agent catalog, attention tabs, and `/demo` declarations unless the override restates them; server-registered TUI plugins may still load with their defaults |

If `cli.json` is not a JSON object, the merge leaves it unchanged and prints a
warning, so a hand edit is never destroyed.

### OpenCode prompt submit keys

In the main prompt composer, Option+Enter sends and Enter inserts a newline.
Shift+Enter, Ctrl+Enter, and Ctrl+J also insert a newline. Nothing in Ghostty
changes. Two seeded `cli.json` keybinds do it:

- `keybinds.input.submit` is `super+return,alt+return`.
- `keybinds.input.newline` is `return,shift+return,ctrl+return,ctrl+j`.

`super+return` is Cmd+Enter. It stays in the list but does nothing out of the
box: Ghostty keeps `super+enter` for fullscreen, so the chord never reaches
OpenCode. It starts working on a host that unbinds it (below), or in another
terminal that delivers it.

Both keys are seeded per key, so a binding you set in **Open settings** or by
hand is never replaced. A seeded key you delete comes back on the next apply; set
it to the value you want instead. The ids bind to any focused textarea, which here
means the composer. The question form's option list and its "type your own
answer" box, dialog prompts, the command palette, and the autocomplete popup
still act on Enter, and Alt+Enter does nothing in dialogs and forms. A permission
prompt also reads Enter in its own layer. That comes from reading the OpenCode
code, not from a live check.

Option+Enter reaches OpenCode as `alt+return` two ways:

- Outside tmux, OpenCode asks the terminal for the kitty keyboard protocol, and
  the chord arrives as `alt+return`.
- Inside tmux with `extended-keys off`, which is tmux's default and which these
  dotfiles leave alone, tmux forwards it as ESC then Enter. OpenCode reads that
  as `alt+return` too.

`alt+return` has to stay out of `input.newline`, where OpenCode puts it by
default. If it is in neither list it still sends through a built-in path.
Ctrl+Enter and Shift+Enter are not send chords because they are OpenCode's native
newline chords, and inside tmux without `extended-keys` they lose their modifier
and arrive as plain Enter. Using Ctrl+Enter to send would need tmux
`extended-keys on` and its removal from `input.newline`.

Things to know:

- An open autocomplete popup eats Option+Enter, and Enter selects the highlighted
  item. After a `/command` or `@file` token, press Esc, then send.
- To use Cmd+Enter on one machine, unbind Ghostty's fullscreen default in
  `~/.config/ghostty/override.conf`. The key name is `cmd+enter`; Ghostty rejects
  `cmd+return`.

  ```text
  keybind = cmd+enter=unbind
  ```

  Cmd+Enter then arrives as `super+return` (kitty protocol) or `ESC[27;9;13~`
  (legacy mode), both read as `super+return`. Inside tmux 3.8 it arrives as
  `alt+return`, because tmux has no Super modifier and folds it into Meta.
  Fullscreen stays on Cmd+Ctrl+F. The unbind is terminal-wide, so every program in
  Ghostty receives the chord, and one that does not know the sequences may print
  or ignore them.
- The `cli.json` keys are not OS-gated. On Debian, and over SSH, Enter also
  inserts a newline, and the send chord is Alt+Enter if the terminal chain
  delivers it.

If Option+Enter does not send, pick one of these:

- Set `macos-option-as-alt = true` in `override.conf`. Option then acts as Alt for
  every key, which also stops Option from composing accented characters. Ghostty
  already defaults to `true` on U.S. layouts and `false` on others, and `left` or
  `right` limits the change to one Option key.
- Change `input.submit` to a chord that does arrive, keeping it out of
  `input.newline`.

To get OpenCode's stock keys back on one host, put this in
`~/.config/opencode/cli.override.json`:

```json
{
  "keybinds": {
    "input.submit": "return",
    "input.newline": "shift+return,ctrl+return,alt+return,ctrl+j"
  }
}
```

To check what Option+Enter sends, open a terminal and run the commands below, then
press Option+Enter within five seconds. The read times out by itself, because Ctrl-D
can itself arrive as an escape sequence once the kitty protocol is on. Skip the two
`printf` lines inside tmux, which does not speak the protocol.

```zsh
old=$(stty -g)
stty -icanon -icrnl -echo min 0 time 50
printf '\e[>5u'    # ask for the kitty protocol, as OpenCode does
cat -v              # press Option+Enter now
printf '\e[<u'     # give the protocol back
stty "$old"
```

In a bare Ghostty window expect `^[[13;3u`. Inside tmux expect `^[^M`. Ghostty's
docs say an Option chord that produces no printable character, which includes
Option+Enter, is treated as Alt whatever `macos-option-as-alt` says, so it arrives
without that setting. Press Option+a too: expect `^[[97;3u` with the protocol on, or
`^[a` with it off. If neither key prints anything, the keyboard or a key remapper is
not sending Option, and the terminal never sees it.

Checked in isolated tmux 3.8 servers against OpenCode 2.1.3: Enter inserts a
newline, Alt+Enter (ESC then Enter) sends, and forms, dialogs, the command palette,
and the autocomplete popup keep acting on Enter.

Checked by hand on 2026-10-23, Ghostty 1.3.1 with `macos-option-as-alt` unset on a
U.S. layout, with the left and the right Option key. Option+Enter arrives as
`^[[13;3u` in a bare window with the protocol on, and as `^[^M` in a bare window
with it off and inside tmux. Inside tmux, Shift+Enter and Ctrl+Enter arrive as plain
Enter, which is why they stay newline chords. A live OpenCode session confirmed
that Enter inserts a newline and Option+Enter sends. Not yet verified: Enter in the
permission prompt.

### OpenCode idle locations

The server config merge seeds `experimental.location_idle_timeout` to `false`
in `~/.config/opencode/opencode.jsonc`, disabling idle location unloading.
Existing values and other experimental settings, including comments, survive.
To reclaim idle locations, set a duration such as `"4 hours"` in that file;
project configuration can override the global value.

This needs OpenCode **2.1.2 or later**, which includes
[#57476](https://github.com/anomalyco/opencode/pull/57476). Its prerequisite
[#57416](https://github.com/anomalyco/opencode/pull/57416) keeps running sessions,
including pending questions and permission prompts, and background jobs loaded
even when an idle timeout is configured. The setting belongs to the server;
when attaching remotely, the connected server needs the update and config.

### OpenCode server plugins

Add server plugins with OpenCode's native CLI, or edit the `plugins` array in
`~/.config/opencode/opencode.jsonc`:

```sh
opencode2 plugin add <package>@<version>
opencode2 plugin list
```

Chezmoi owns the registrations between `// dotfiles:plugins:start` and
`// dotfiles:plugins:end`, including their `@latest` references and audit comments.
Both Pillbox and Sidequest follow npm's moving `latest` tag. OpenCode checks
for newer versions on startup but keeps the installed versions until you choose
to update them. Review the release, then run `opencode2 plugin update` to install
the latest available versions. This executes new plugin code without a dotfiles
change. The `opencode2` wrapper runs with `NPM_CONFIG_MIN_RELEASE_AGE=0` (see
[OpenCode updates](#opencode-updates)), so your npm release-age policy does not
reject a fresh version there; reviewing the release is the control. A fresh
installation also resolves the moving tags at startup.
Keep local entries after the end marker. Packages, local paths, Git references,
object options, and comments survive repeated applies in their original local
order. There is no dotfiles allowlist; review additions yourself because plugins
execute code in OpenCode's process.

This example omits the generated audit comments:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": [
    // dotfiles:plugins:start
    "opencode-pillbox-statusline@latest",
    "opencode-sidequest@latest",
    // dotfiles:plugins:end
    {
      "package": "@example/reviewer@1.2.3",
      "options": { "strict": true }
    },
    "./v2-plugins/local/reviewer",
    "-pillbox"
  ]
}
```

OpenCode processes controls in order. A local `-pillbox` control after the
managed section disables the plugin with that id, pillbox's server half. Wildcard controls are also
preserved, without sorting or deduplication. See the
[V2 plugin guide](https://opencode.ai/v2/docs/plugins/#control).
CLI-only plugins still belong in `cli.override.json`; this merge does not change
their ownership.

Sidequest's server id is `sidequest`; its terminal id is `sidequest.tui`. Disable
the server with `-sidequest` after the managed section and the terminal half
with `-sidequest.tui` in `cli.json.plugins` when turning off the whole plugin.

You can change a managed string registration to an object with `package` and
`options` inside the marked section. Dotfiles owns its `@latest` reference; local
options and their comments survive reference updates. When a later dotfiles revision
retires a managed registration, it removes that registration only. It does not
delete independently added entries, plugin installations, or runtime data.

The first apply adopts a single matching existing registration,
such as `opencode-pillbox-statusline@latest`, including the object form.
Other unmarked V2 entries remain local. A competing version, duplicate
registration, malformed JSONC, or ambiguous marker pair produces a warning and
leaves the entire target unchanged. The rest of the apply can continue.

Resolve a conflict by keeping one registration in the managed section at the
dotfiles reference, moving any local options into that object, and removing the
competing entry. A different managed reference requires a source change;
a disable control does not transfer version ownership. The existing retirement
of the singular V1 `plugin` key is unchanged.

### Ordering

Ghostty defers included files until after the config that names them, so its
`config-file` line can sit anywhere. Zsh, Git, Neovim, and tmux load inline. The
first three keep their override at the bottom of the managed config.

tmux uses this sequence:

| Phase | Action |
| --- | --- |
| 1 | Load managed tmux options and `conf.d` files |
| 2 | Source optional `~/.tmux/conf.d/override.conf` |
| 3 | Rebuild enabled managed defaults in `@tpm_plugins` |
| 4 | Run TPM as the final executable line in `~/.tmux.conf` |

Plugin-specific options and local literal `@plugin` declarations are therefore
available when TPM starts plugins. This ordering is intended for options that a
plugin reads as input. Generic settings that a plugin unconditionally writes are
not guaranteed to be last-wins because the plugin starts after `override.conf`.
Use the plugin's documented options instead.

Neovim has the same shape. The `pcall` runs after `require("lazy").setup()`
returns, so `override.lua` covers options, keymaps, autocmds, and per-machine
LSP paths, but cannot add lazy plugins and cannot beat a lazy-loaded plugin's
own config, which runs on demand later. Use a spec import or an autocmd for
those.

Git applies includes inline too, so the override include is last in
`~/.gitconfig`. Verify with `git config --list --includes --global`, not
`--get`: `--includes` defaults off when a file scope like `--global` is given,
so `--get` silently reports the pre-include value.

### `~/.zsh_override` vs `~/.zsh_private`

Two files, two jobs:

- `~/.zsh_override` is for changing this config. Aliases, functions, options,
  keybinds, completion. `.zshrc` sources it last, so it beats the managed
  aliases, Oh My Zsh, and the custom functions.
- `~/.zsh_private` is for credentials, private env vars, and work-specific
  settings. `.zshrc` creates it on first run and sources it early, so the
  aliases and functions loaded afterwards can use what it defines.

Local shell functions belong in `~/.zsh_override` rather than
`$ZSH_CUSTOM/functions/`, which `.zshrc` globs and chezmoi manages. A blanket
ignore there would un-manage the real function files, so anything you do drop in
that directory should be named `local-*.zsh`, which `.chezmoiignore` guards.

### Backups

`run_before_00-backup.sh` skips `$HOME` itself but sweeps every directory that
holds a managed file. The hatches under `.config/` and `.tmux/` are therefore
copied in plaintext into `~/.dotfiles-backup/`, with 20 snapshots retained.
`~/.zsh_override` and `~/.zsh_private` sit loose in `$HOME` and are never swept,
which is the right place for anything sensitive.

The same script also clears fresh-install conflicts. chezmoi overwrites a plain
pre-existing file, but it aborts the whole apply when a target already exists as a
different filesystem type than the one it manages: a symlink or file where a
directory goes (a symlinked `~/.config/nvim` is the common case), or a directory
or special node (FIFO, socket, device) where a file or symlink goes. Before
applying, the script moves each such target into the current snapshot as
`<name>.pre-apply` so the apply proceeds. Only a genuine type mismatch is moved:
a directory that chezmoi also manages as a directory (`~/.config`, `~/.claude`,
`~/.codex`, `~/.local`) is left in place to merge, so that holds only when those
paths are real directories. Recover an original from
`~/.dotfiles-backup/<timestamp>/<relative-path>.pre-apply`.

Two inaccessible-directory cases are handled before chezmoi can trip on them. A
`~/.claude` you own but cannot search gets `chmod u+rwx` from the same script when
the managed skills link is selected, so its legacy skills are reviewed and backed up
instead of replaced; see [Cross-harness agent skills](agent-skills.md#selection-and-layout).
A `~/.codex` you cannot search used to fail every apply with
`lstat ~/.codex/themes/gud.tmTheme: permission denied`. Chezmoi reads
`.chezmoiremove` before any script runs, so a hook cannot fix that first. The
template there now lists the old Codex theme only when the owner can search
`~/.codex`. Chezmoi repairs the mode of the directory it manages, and the next
apply removes the theme. The gate tests the owner's search bit, so a `~/.codex`
owned by another account is not covered. Because the directory is unreadable on
that first run, its managed files are not copied into the snapshot, though the
Codex config merge still preserves their local keys.

### Reloading

```sh
ghostty +validate-config          # then reload Ghostty's config
tmux source-file ~/.tmux.conf
exec zsh
git config --list --includes --global
```

The tmux reload applies new configuration but cannot tear down state left by an
already-loaded plugin. Restart the tmux server after disabling a plugin.

## Terminal (tmux) behavior

`prefix + m` toggles tmux mouse capture. The two states trade tmux-native
selection against Ghostty-native selection:

| `prefix + m` | Behavior |
| --- | --- |
| on | tmux mouse capture: tmux drag-select and `tmux-yank` copy to the system clipboard with no Shift |
| off | Ghostty native selection across panes; this also disables tmux scroll and mouse pane-select until you toggle back (by design) |

Single-pane copy needs no toggle. Enter copy mode, drag to select, and press `y`
to copy. Mouse capture is on by default.

Use `prefix + m` for cross-pane native selection, when you want the terminal to
own the whole grid.

A wheel-up event always enters tmux copy mode, even when the foreground TUI has requested
application mouse reporting. Ghostty-over-SSH therefore scrolls tmux history instead of handing
the wheel to the TUI.

A flagged notification pane clears when it regains focus or receives ordinary
keyboard input, a primary click, a drag, or a scroll event. Only that pane is
cleared. Normal mouse behavior and right-click menus are left alone.

Session and window names are set automatically. `tmux ls` reads by project,
while window tabs read by task:

| Name | Source |
| --- | --- |
| Session | the project root (git toplevel basename, else cwd basename), set by a zsh `chpwd` hook (`home/dot_zsh/custom/functions/tmux-session-name.zsh`); a name you set manually via `prefix + $` is respected |
| Window | tracks the foreground command via tmux `automatic-rename` (`#{pane_current_command}`) |

So `tmux ls` shows project names while the window tabs show `1:zsh`, `2:nvim`, `3:git` live.

### Status bar

The tmux status bar renders session, host, window tabs, network, CPU, RAM, and
date/time as separate rounded pills. Each color comes from the selected shared
palette. The active window uses the palette's green accent. A notification keeps
its group accent from `notify.yaml`, which is also rendered from that palette.

## Statusline (Claude / Codex)

The `ai > statusline` sub-feature installs a custom Claude Code statusline and a
matching Codex theme. It also installs `jq` and `python3`.

The renderer parses stdin with `jq`. A detached Python updater calculates the
subagent-inclusive token total away from the render path. Claude groups related
segments with a grey `│` and separates items inside a group with `·`:

| Group | Segments |
| --- | --- |
| identity | model; context (usage bar + percent, plus used/max at wider widths) |
| usage | cumulative token total (subagent-inclusive Sigma); session duration |
| limits | 5-hour and weekly rate bars |
| git | branch and dirty state |

Rate bars disappear when the payload has no `rate_limits`. Corporate and
enterprise Claude contracts commonly omit that field.

### Auto-width

Claude Code v2.1.153 and later exports `COLUMNS` and `LINES` to the statusline
command. Because stdout is captured, `tput cols` cannot inspect the terminal.
The stdin JSON has no width either, leaving `COLUMNS` as the useful signal.

The renderer uses it to widen bars or drop lower-priority segments:

| Tier | `COLUMNS` | Context bar | Rate bar | Drops |
| --- | --- | --- | --- | --- |
| wide | 115 or more | 16 | 12 | nothing |
| med | 80 to 114, or unset | 10 | 8 | nothing |
| narrow | 55 to 79 | 8 | 6 | used/max detail |
| tiny | under 55 | 6 | hidden | used/max, duration, rate bars |

When `COLUMNS` is unset, the renderer uses the `med` tier. This covers older
Claude versions, pipes, and non-interactive callers.

Bar widths, dropped segments, and divider glyphs are simple settings near the
top of `~/.claude/statusline-command.sh`.

Codex uses its native footer with the same selected palette. It shows model and
reasoning, run state, task progress, context use, session tokens, limits,
project root, and Git branch. Unavailable values are omitted.

The theme uses cyan for the model, pink for state, green for progress and
branch, purple for usage, orange for limits, and yellow for paths. It is
rendered to `~/.codex/themes/dotfiles.tmTheme`.

This is Codex's built-in `tui.status_line`, configured by the chezmoi merge
template. Codex does not currently support a command-backed footer, so it
cannot use Claude's custom glyphs, subagent token total, session duration, or
adaptive width tiers.

## OpenViking memory

`ai > openviking` provides starter profiles and native user-service wiring.
The live `~/.openviking/ov.conf` and `ovcli.conf` remain private and unmanaged.
Use `openvikingctl stop` before deselecting the component; configuration and
memory are retained. See [OpenViking local memory](openviking.md) for setup,
provider selection, and performance measurements.

## SSH MCP for OpenCode V2

Selecting `ai > opencode` installs the npm `latest` release of `ssh-mcp` and seeds
`mcp.servers.ssh-mcp` disabled. It has no individual picker entry.
In package mode, each `chezmoi apply` or `chezmoi update` checks for a newer
release and offers it in the package plan. The approved version is installed;
configs-only mode does not check or upgrade packages. Package confirmation is
still required for a pending upgrade unless unattended mode is explicitly enabled.
It uses a local stdio connection; no remote SSH service or key is installed by
dotfiles.

The managed starter is at
`~/.local/share/dotfiles/ssh-mcp/config-starter.toml`. Copy it to your private
SSH MCP config (`~/.config/ssh-mcp/config.toml` on Linux, or
`~/Library/Application Support/ssh-mcp/config.toml` on macOS), add only the
hosts you want accessible, and set the directory to mode 0700 and file to
0600. The starter requires approval for every command; its example profile
is commented out. Use an SSH agent or a private key reference, and verify and
pin each host's fingerprint before connecting. The upstream SSH transport
does not use OpenSSH's `known_hosts`; without a pin, trust on first use is
forgotten when the MCP process restarts.

The private TOML, keys, SSH config, and host profiles are not managed. The
OpenCode merge adds `ssh-mcp` only when absent and never replaces a local entry.
Chezmoi installs the public starter directory with owner-only access (`700`);
the live host-profile configuration remains separate and unmanaged. A repeated
apply should not loosen either directory or produce a mode-only status diff.
To enable it, set `"disabled": false` on `mcp.servers.ssh-mcp` in your global
`~/.config/opencode/opencode.jsonc` and reload OpenCode. Set it back to `true`
to turn it off. Chezmoi preserves either choice on subsequent applies.
Deselecting OpenCode stops future package
checks but does not delete a previously installed binary or registration;
disable the entry before deselecting it. OpenCode tool permissions and the
SSH MCP profile's role and approval rules are independent checks.

## Caveman compression

Selecting OpenCode installs the CLI, signed companions, and two upstream
skills, and seeds its recovery MCP disabled. Its V2 plugin reads an enabled
private route. Follow [Caveman setup and recovery](caveman.md); user-service
activation and OC2 reload are deliberate steps, not apply side effects.
Chezmoi keeps both upstream skill directories at `700` across repeated applies;
the files retain their separately pinned external sources.

## Secret scanning

Mason installs Gitleaks for Neovim. Normal buffers are scanned asynchronously
after read and save. Findings are warning diagnostics and never block either
operation.

The official pinned prek hook is the enforcement boundary:

```sh
prek run gitleaks --all-files
```

See [Gitleaks](gitleaks.md) for exclusions, project allowlists, and
troubleshooting.

## Docker and Terraform checks

Neovim uses Docker's official language server for Dockerfiles and standard
Compose filenames. For repository checks, use the first-party validators:

```sh
docker build --check .
docker compose config --quiet
```

Terraform runs through tenv's project-aware proxy. It honors project version
files and `required_version`, installs missing versions, and verifies HashiCorp
signatures.

Package bootstrap never waits indefinitely on tenv's `Terraform.lock`. A recent
lock, or an old lock with a running tenv process, skips the Terraform fallback
step while the rest of the package run continues. An old ownerless regular file
is removed as stale before tenv runs.

```sh
tenv tf install 1.15.7       # explicitly install a Terraform release
tenv tf use -w 1.15.7        # write .terraform-version in this project
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

Mason installs TFLint for Neovim. Terminal and CI workflows should use the
project's own TFLint provisioning. The managed `~/.tflint.hcl` enables only
TFLint's portable recommended rules. Cloud-provider rulesets belong in each
project; an AWS plugin has no business loading in every Terraform repository.

## Supported platforms

| Platform | Package manager |
| --- | --- |
| macOS | Homebrew |
| Debian Trixie | `apt-get`, with sudo |

Headless CI deploys both rows from scratch. Ubuntu and other Linux
distributions may work when the listed binaries are installed, but they are not
deployment-gated.

## Uninstall

```sh
chezmoi purge          # removes chezmoi source and state
rm -rf ~/.zsh ~/.tmux ~/.config/nvim ~/.config/yamllint ~/.local/share/nvim-venv
rm -f ~/.zshrc ~/.zshenv ~/.tmux.conf
rm -f ~/.darglint ~/.flake8 ~/.tflint.hcl ~/.markdownlint.yaml
rm -f ~/.gitignore_global ~/.local/bin/tenv ~/.local/bin/terraform
rm -rf ~/.tenv
rm -f ~/dotfiles    # convenience symlink created by install.sh
```
