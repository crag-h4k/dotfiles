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
