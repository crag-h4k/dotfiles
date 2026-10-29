# Decisions behind the guidance

Reviewed on 2026-10-02 against repository commit `b2a055c`, available Codex and
OpenCode user messages, saved plans, and maintainer memory. This record contains
sanitized decisions. Account chat archives unavailable to the reviewing tools
were not inspected. Public commit IDs identify implementations; dates identify
explicit user corrections. Recheck behavior in the checkout being changed.

## Firm choices

| Evidence | Decision | Current consequence |
| --- | --- | --- |
| User corrections, 2026-06-28 | Preserve macOS compatibility and collect/deduplicate selected packages before manager operations | Shared planning and batched installs; bootstrap prerequisites may precede the batch |
| User corrections, 2026-06-28 and 2026-07-25 | Detect whether APT already uses a repository, regardless of filename; use Deb822 for new sources | Reuse valid sources/keyrings and test alternate-keyring installations |
| User decisions, 2026-07-18; `3743d69` | Package changes need a preview and approval; configs-only remains useful | Preserve default-no confirmation and explicit unattended package/update opt-ins |
| User corrections, 2026-07-25 through 2026-07-27; `65b8609`, `6caa069` | Scrolling and notifier clearing must work through Ghostty, SSH, and tmux | Exercise real input behavior without sacrificing drag-copy or wheel bindings |
| User decisions, 2026-07-25 through 2026-07-29; `02d4945` | Deployment success includes launched applications; complete CI matters more than selective speedups | Both platforms build/install/smoke; improve speed with caching and parallelism |
| User decisions, 2026-07-25 through 2026-07-26; `59e7559`, `7247712` | Keep the repo root tidy and managed state separate from project infrastructure | `home/` is the source root; scripts/tests/docs/CI remain outside it |
| User writing decisions, 2026-07-26; `7dd22ea` | Irreverent README, calmer engineering docs, readable line breaks, compact badges | Preserve the existing voice, avoid public "rice" terminology, foreground the notifier |
| User decisions, 2026-07-25 through 2026-07-27; `7dd22ea` | Worktrees and reviewable feature branches; Conventional PR titles and deliberate SemVer releases | Preserve squash/main workflow and Release Please's pending release PR |
| User decisions, 2026-07-30 through 2026-07-31 | Share portable AI assets without taking over private/work assets | One canonical store with per-entry overlays and public-safe authored content |
| User decisions, 2026-09-03; `618d463`, `a123271`, `c7d452d` | Coherent statuslines and useful provider usage across the supported tools | Shared palette, monthly and available weekly limits; usage at the footer's far right |
| `769729b`, `1aaede3`; user corrections, 2026-10-02 | Local settings, permissions, and routing belong in unmanaged override hatches | Preserve generic source configuration and private overlays |
| `7247712`, `2d0dffc`; user corrections, 2026-10-01 through 2026-10-02 | OpenCode V2 needs a compatible isolated CLI/runtime and private routing | Validate before activation and preserve previous releases and local runtime state |
| Explicit switch, 2026-09-28; `c9aee8b` | Local hooks and CI use prek | Retain `.pre-commit-config.yaml` as hook configuration and use prek commands |
| `caeaa06`; shared-skill implementation at the reviewed baseline | Handoffs and writing skills share one store without whole-directory takeover | Per-skill links; immutable third-party pins/checksums; explicit-only Humanizer |
| User corrections, 2026-10-02; `b2a055c` | Current packages should skip installation; native/editor package candidates need detail | Resolve versions/revisions once for approval and consume those records |
| User requests, 2026-10-02; `b2a055c` | Keep install logs accessible and demos inexpensive; investigate Termius display failures | Preserve log interface, local demo/diagnostics, and terminal-chain regression tests |
| User choices for this guidance, 2026-10-02 | Repository-only guidance, shared skill primarily for OpenCode2, lean entrypoints, upkeep with changes | Exclude AGENTS from deployment; keep installed assets untouched during source-only work |
| User decisions, 2026-10-15 through 2026-10-16 | Move the OpenCode V2 footer into the standalone, config-driven `opencode-pillbox-statusline` package | Exact-pin it in both config files; seed theme-token color options in `cli.json`; keep Copilot tiers opt-in; keep `/demo` as a small local plugin without diagnostics |
| User decisions, 2026-10-17 | Integrate Sidequest alongside Pillbox while retaining the dotfiles leader | Match server/TUI pins, seed Sidequest's `focusKey` to `<leader>p`, and preserve custom options; verify both first npm releases before deployment |
| User decision, 2026-10-19 | Return the leader to OpenCode's default `Ctrl+X`, superseding the 2026-10-17 choice to keep `Ctrl+G`; keep the tab navigation keys as the managed customizations | Enforce the leader and the navigation keys; release the pane, terminal, and terminal-toggle defaults they displace so no two managed actions share a chord |
| User decision, 2026-10-20 | Chezmoi-driven npm work and the managed `opencode2` wrapper bypass the user's npm release-age cooldown | Export `NPM_CONFIG_MIN_RELEASE_AGE=0` in process environments only (`scripts/common.sh`, runtime sync, candidate resolver, wrapper); never edit npm config files or add per-package exceptions |
| User decision, 2026-10-20 | Keep git worktrees and the local agent notes (plans, specs, drafts, handoffs) in two configurable directories instead of a per-host layout | `data.worktreesDir` (default `$HOME/worktrees`, flat `<root>/<repo>-<slug>`) and `data.agentsDir` (default `$HOME/agents`) keep their saved value on re-init; `DOTFILES_WORKTREES_DIR` and `DOTFILES_AGENTS_DIR` only seed a first init; apply creates the directories and prints the privileged command instead of running it; `~/.zshenv` exports both variables for skills and agents |
| User decision, 2026-10-20 | Ask for the worktrees and agent-notes directories at init, and let Plan mode save handoffs under the agent-notes directory (the always-on prompt pages are superseded by the next row) | Prompt at the end of the AI submenu, pre-filled with the saved value, then the env seed, then the default; skip it for `DOTFILES_NO_TUI`, no usable terminal, `cup`, or an unselected AI component, and never prompt during `apply`; Gum input when installed, a typed prompt otherwise; answers are validated through `dotfiles-dir` and asked again, then fail with its error; the managed Plan permissions add `<agentsDir>/plans` rendered from the same template, regenerated in place on every apply |
| User decision, 2026-10-20 | Do not give the two directories their own init pages; fold them into the AI page as "checkbox + one editor, prefilled with defaults and the last selection" | An unchecked `directories` entry on the AI page (an init-time action, never a component and never saved in `aiSelection`) is the default and asks nothing; checked, one `gum write` page holds both paths (a typed host gets two `promptString` questions), pre-filled with the saved value, then the env seed, then the default; the entry is not offered under `DOTFILES_NO_TUI`, without a usable terminal, on `cup`, or for the `all+` migration; answers are parsed leniently, validated through `dotfiles-dir`, reopened with the text kept up to three times, then fail with its error |
| Maintainer finding, 2026-10-20 | A user-owned `~/.claude` at mode 000 hid a real skills directory from the pre-apply hook, and chezmoi then replaced it with the link without a backup; a user-owned `~/.codex` at mode 000 failed every apply because chezmoi reads `.chezmoiremove` before any script runs | The hook restores owner access (`chmod u+rwx`, owner bits only, no symlinks, warn and continue on failure) to `~/.claude` while the skills link is managed, so the review gate runs; `.chezmoiremove` lists the old Codex theme only when the owner can search `~/.codex`; a hook-side repair of `~/.codex` cannot run early enough and was not used |
| User decision, 2026-10-20 | Route OpenCode's own GitHub Copilot login through a named Caveman compat mount; the installed proxy already serves it | The hook routes only the configured upstream origin and prefix and forwards the path below it unchanged; Anthropic Messages takes the route only with `wire_dialect: anthropic`, which `cavemanctl` renders onto the mount; everything else stays direct |
| User decision, 2026-10-22, revised 2026-10-23 | In the OpenCode V2 prompt composer, Enter inserts a newline and Option+Enter sends; Ghostty's defaults stay untouched. The first design (Cmd+Enter sends, with `cmd+enter=unbind` in the macOS Ghostty arm) was dropped on 2026-10-23 | Seed `input.submit` (`super+return,alt+return`) and `input.newline` (`return,shift+return,ctrl+return,ctrl+j`) in `cli.json`; `alt+return` stays out of newline; `super+return` stays listed but is inert unless a host unbinds `cmd+enter` in its own `override.conf`; Ctrl+Enter and Shift+Enter were rejected as send chords because they are OpenCode's native newline chords and lose their modifier inside tmux without `extended-keys`; Option+Enter delivery was checked by hand on 2026-10-23 in a bare Ghostty 1.3.1 window with `macos-option-as-alt` unset and inside tmux, and a live OpenCode session sent a prompt with it; the permission prompt's Enter is unverified |
| User decision, 2026-10-23 | Syncing a feature branch with its base is pre-approved for agents: fetch the base and merge it with the message `chore: merge <base> into <branch>`; a push of the result still asks | Past approvals do not carry over, so the exception is written into the managed global OpenCode instructions, the ricer agent and the git-publish skill, each limited to a plain merge with no rebase or force. A conflict aborts the merge and is reported instead of being resolved. |

## Defaults that can be changed

Gud remains the default Zsh prompt; Dracula remains the default catalog palette.
Earlier maintainer feedback rejected imposing an unrelated house palette. The
current selectable catalog and saved `data.palette` take precedence over that
default. Do not turn the old preference into a ban on user-selected schemes.

Prefer existing integration points, focused changes, and useful diagnostics over
adding another framework or copying every historical workaround into policy.
These are maintainer defaults inferred from repeated corrections about clutter,
duplication, scope growth, silent phases, and deployment failures. A current
explicit request can choose a different approach.

## Superseded assumptions

- Managed dotfiles no longer live directly at the repository root. Commands use
  the repo root as `--source`; `.chezmoiroot` directs chezmoi into `home/`.
- Generic Git configuration is managed. Identities are private and unmanaged.
- Statuslines are implemented. OpenCode V2 has its own selection and plugins.
- The old static Gud theme file is not the canonical color source. The committed
  catalog feeds consumer templates; its generator runs at authoring time.
- Pre-commit is no longer the runner name. The hook configuration filename stays.
- Historical proposals for shared AI trees, third-party submodules, or a develop
  branch do not establish current architecture. Check what actually landed.
- Do not retain an old installer's diagnosis as a permanent claim about a distro
  package or upstream API. Resolve the versions involved in the current failure.

## Refresh policy

Update rules when their behavior or an explicit durable choice changes. Add a
dated basis here only when it helps a later maintainer avoid relitigating the
decision. Remove superseded detail when it no longer explains a likely mistake.
Do not carry historical operation approvals into current permissions or add raw
transcripts, session IDs, private identities, machine paths, or account details.
