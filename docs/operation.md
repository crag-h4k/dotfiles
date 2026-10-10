<!-- docs/operation.md -->
# Operation

## Table of Contents

- [Daily operation](#daily-operation)
- [Telemetry opt-outs](#telemetry-opt-outs)
- [OpenCode updates](#opencode-updates)
- [Local overrides](#local-overrides)
  - [Shell PATH additions](#shell-path-additions)
  - [OpenCode server plugins](#opencode-server-plugins)
- [Terminal (tmux) behavior](#terminal-tmux-behavior)
  - [Status bar](#status-bar)
- [Statusline (Claude / Codex)](#statusline-claude--codex)
- [OpenViking memory](#openviking-memory)
- [SSH MCP for OpenCode V2](#ssh-mcp-for-opencode-v2)
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

Config-only mode skips package work. A headless apply without
`DOTFILES_ASSUME_YES=1` declines package changes. The direct chezmoi external
refresh flag can still refresh Git externals before the installer runs; omit it
to use the installer's cleanliness and fast-forward checks.

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
under `~/.local/share/opencode2`. The wrapper passes that prefix to npm. It also
exempts the `@opencode/*` release family from npm's release-age filter because
the native updater requests an exact new CLI version and platform package.
The matching runtime exempts both `@opencode/*` and `@opentui/*`: a fresh SDK can
require OpenTUI packages published the same day. Other packages retain the
user's release-age guard, and dotfiles does not modify `~/.npmrc`.

Runtime synchronization reads the installed CLI's SDK peer requirements, then
uses npm's age-aware resolver for compatible OpenTUI and Solid.js candidates.
Installation consumes those exact versions. Missing peer metadata or unresolved
candidates stop the sync before npm changes the existing runtime; there is no
fallback to an unconstrained `latest` tag.

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

With `ai > opencode` selected, chezmoi also merges a portable preference into
`~/.config/opencode/AGENTS.md`: use the `question` tool when asking how to
proceed or how to evaluate options. Existing local instructions stay intact.
Its OpenCode config merge adds Plan handoff access for the two documented roots
without replacing unrelated local Plan rules. Host-specific roots still need a
private permission overlay.

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
the rest of `.zshrc` and the installed `.zshenv` exactly match managed source.
The full original remains in the uniquely named pre-apply snapshot.

Other local edits, symlinked targets, and changed `.zshenv` files are left alone.
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

### OpenCode server plugins

Add server plugins with OpenCode's native CLI, or edit the `plugins` array in
`~/.config/opencode/opencode.jsonc`:

```sh
opencode2 plugin add <package>@<version>
opencode2 plugin list
```

Chezmoi owns the registrations between `// dotfiles:plugins:start` and
`// dotfiles:plugins:end`, including their package pins and audit comments.
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
    "opencode-copilot-statusline@1.0.0",
    // dotfiles:plugins:end
    {
      "package": "@example/reviewer@1.2.3",
      "options": { "strict": true }
    },
    "./v2-plugins/local/reviewer",
    "-opencode-copilot-statusline"
  ]
}
```

OpenCode processes controls in order. A local `-opencode-copilot-statusline`
after the managed section disables the quota plugin. Wildcard controls are also
preserved, without sorting or deduplication. See the
[V2 plugin guide](https://opencode.ai/v2/docs/plugins/#control).
CLI-only plugins still belong in `cli.override.json`; this merge does not change
their ownership.

You can change a managed string registration to an object with `package` and
`options` inside the marked section. Dotfiles owns its package version; local
options and their comments survive pin updates. When a later dotfiles revision
retires a managed registration, it removes that registration only. It does not
delete independently added entries, plugin installations, or runtime data.

The first apply adopts a single exact existing
`opencode-copilot-statusline@1.0.0` registration, including the object form.
Other unmarked V2 entries remain local. A competing version, duplicate
registration, malformed JSONC, or ambiguous marker pair produces a warning and
leaves the entire target unchanged. The rest of the apply can continue.

Resolve a conflict by keeping one registration in the managed section at the
dotfiles pin, moving any local options into that object, and removing the
competing entry. A different managed version requires a reviewed source change;
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

Select `ai > ssh_mcp` alongside `ai > opencode` to install the pinned
`ssh-mcp` CLI and seed `mcp.servers.ssh-mcp` in OpenCode V2 as disabled. This
is a separate, default-off choice. Package approval is required for the binary.
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
To enable it, set `"disabled": false` on `mcp.servers.ssh-mcp` in your global
`~/.config/opencode/opencode.jsonc` and reload OpenCode. Set it back to `true`
to turn it off. Chezmoi preserves either choice on subsequent applies.
Deselecting the component stops future package
checks but does not delete a previously installed binary or registration;
disable the entry before deselecting it. OpenCode tool permissions and the
SSH MCP profile's role and approval rules are independent checks.

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
