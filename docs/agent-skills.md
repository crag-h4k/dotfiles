<!-- docs/agent-skills.md -->
# Cross-harness agent skills

## Table of Contents

- [Selection and layout](#selection-and-layout)
- [Harness support](#harness-support)
- [Invocation](#invocation)
  - [Dotfiles maintenance](#dotfiles-maintenance)
  - [Handoff](#handoff)
  - [Git publishing and review](#git-publishing-and-review)
  - [Unslop](#unslop)
  - [Humanizer](#humanizer)
- [Provenance and pins](#provenance-and-pins)
  - [License boundaries](#license-boundaries)
  - [Update audit](#update-audit)
- [Threat boundaries](#threat-boundaries)
- [Validation](#validation)

## Selection and layout

Shared skills install automatically when any existing `ai` sub-feature
is selected. There is no separate skill picker or `writing_quality` flag. A host with
every `ai` sub-feature disabled gets none of these assets.

The only canonical copies live under `~/.local/share/agent-skills/`:

```text
~/.local/share/agent-skills/
├── PROVENANCE.md
├── chezmoi-dotfiles/
├── handoff/
├── git-publish/
├── pr-watch/
├── git-worktree/
├── humanizer/
├── unslop-code/
├── unslop-text/
└── unslop-ui/
```

Chezmoi creates one relative symlink per skill under both `~/.claude/skills/`
and `~/.agents/skills/`. It never replaces either skills directory. Existing
and future skills beside these nine remain untouched.

Selecting `ai > openviking` adds three unmodified upstream instruction skills:
`openviking-memory`, `openviking-skills`, and `ov-experience-memory`. They follow
the same canonical-store and per-entry-link pattern, but their downloads and
links are gated on OpenViking only. Native discovery avoids the plugin's
unsupported skill-directory API. See [OpenViking local memory](openviking.md)
for the separate hook and authenticated MCP connections.

## Harness support

| Harness | Discovery root | Notes |
| --- | --- | --- |
| Claude Code | `~/.claude/skills` | Native skill discovery; Humanizer uses `disable-model-invocation: true` |
| CodeCompanion | `~/.claude/skills` | Uses the Claude-compatible skill root |
| Codex | `~/.agents/skills` | Native skill discovery; Humanizer's `agents/openai.yaml` disables implicit invocation |
| OpenCode V2 | `~/.agents/skills` | Native compatibility root; also sees `.claude`, but both links resolve to the same canonical directory and one effective ID |
| GitHub Copilot | `~/.agents/skills` | Native personal skill discovery; Humanizer uses explicit-only frontmatter |

OpenCode commands live at `~/.config/opencode/commands/dotfiles.md`,
`~/.config/opencode/commands/handoff.md`,
`~/.config/opencode/commands/unslop.md`, and
`~/.config/opencode/commands/humanize.md`,
`~/.config/opencode/commands/publish.md`,
`~/.config/opencode/commands/pr-watch.md`, and
`~/.config/opencode/commands/worktree.md`. They are prompt-only Markdown with no
shell interpolation.

Other harnesses are unsupported. A future integration should warn and continue
rather than fail chezmoi apply or create a parallel skill copy.

## Invocation

### Dotfiles maintenance

`chezmoi-dotfiles` is available for normal model selection and supports this
workstation repository, primarily through OpenCode2. It loads scoped guidance
and the references needed for the current task. Use OpenCode's prompt-only router:

```text
/dotfiles
/dotfiles diagnose a repeated package update
/dotfiles refresh-guidance
```

No arguments reports orientation without edits. `refresh-guidance` explicitly
reviews available history and current behavior; routine maintenance does not scan
all chats. A task keeps its authorized scope and execution mode. The command and
skill grant no tool permissions and do not automatically deploy or publish.

The canonical `SKILL.md` and references are first-party read-only assets. Read
the source skill directly when working on a checkout before its normal apply.
See [Agent guidance](agent-guidance.md) for the scoped contracts and evidence.

### Handoff

`handoff` is available for normal model selection. In OpenCode, use:

```text
/handoff
/handoff resume <project>
/handoff integrate <project>
/handoff list
/handoff close <project>
```

Save writes a new file only on an explicit save. Resume reads the newest open
file, re-checks live state, reports drift, and stops. It does not start work.
Integrate does the same verification, incorporates the validated context into
the current session, and leaves the handoff open. It does not execute Next steps
unless the current request authorizes them. In Plan mode the skill and read-only
snapshot script remain available; only files under the configured handoff root
can be edited for save or close, not project files.
With `ai > opencode` selected, the managed Plan permissions allow edits to
`<Project>/<slug>-handoff-<YYYY-MM-DD>.md` under
`~/.local/share/agent-handoffs/` and `/opt/ai/handoffs/`. Sensitive file
suffixes and other filenames are denied inside those roots. Review any
later private Plan rules before relying on that boundary. The rules also allow
external access to the installed handoff snapshot script. Use the home path as
the handoff root on a new machine, or configure a narrow private rule for a
different root. The skill still requires the root in the request or harness
instructions; the permission rule does not choose or create it. A higher-priority
harness policy can still block edits.
The handoff root comes from the user or from harness instructions. The skill
does not invent one. The snapshot script prints git state only. It does not
print the environment or file contents. Chezmoi installs it read-only and
executable so the skill can invoke it directly. A draft that contains a private-key
block, a cloud access key, a service token, or a password assignment is not
written.

### Git publishing and review

Three read-only instruction packages adapt MIT-licensed EveryInc workflows:

| Skill | OpenCode command | Behavior |
| --- | --- | --- |
| `git-publish` | `/publish <change>` | Explicit staging, commit-message choices, approved push and template-based PR creation/update. |
| `pr-watch` | `/pr-watch <PR>` | Bounded CI watching and review-feedback checkpoints; no automatic fixes or external writes. |
| `git-worktree` | `/worktree <task or ref>` | Approved isolation using the repository's worktree layout; no silent switching or cleanup. |

They work through native skill discovery in standalone OpenCode V2 and the
other supported harnesses; OpenChamber is not required. They install with any
selected AI sub-feature, not with the unconditional Lazygit package. Their
normal skill discovery remains enabled, but invocation never grants write
permission. In OpenCode, decisions and Git approvals use `question`; other
harnesses use their available blocking question tool. Only a non-OpenCode
harness lacking such a tool may fall back to chat. OpenCode stops writes until
`question` works; errors and dismissed questions are not approval.

Publishing preserves unrelated index entries and stops on mixed user/task edits.
Before a commit it presents at least two Conventional Commit messages and asks
for a choice and explicit authorization. Push/PR changes use the verified head
and base repositories, including fork differences. Review uses an existing
review skill rather than installing EveryInc's multi-agent review framework.

PR monitoring defaults to a ten-minute bounded CI wait; `checkpoint` takes one
snapshot. Reviews and inline unresolved threads are inspected before and after
the wait, not streamed continuously. Changing the head invalidates earlier green
checks. No checks, failed API reads, incomplete thread pagination, or unknown
review requirements cannot establish merge readiness. Failures and feedback
go through question-tool decisions; fixes, Git writes, replies, resolutions,
CI reruns, and merge require their own scoped authorization. Monitoring ends
when checks finish, the budget expires, or it reaches a blocker; it does not
leave a daemon running. No autonomous EveryInc babysitter is installed.

Worktree setup detects an existing checkout before proposing another. It follows
configured host/repository paths instead of assuming `.worktrees/`, asks before
fetch/create/switch operations, and moves the primary session to a newly created
tree only with available host support. Independent feature work does not reuse
another task's worktree. Branches and trees remain after merge unless cleanup
is separately authorized.

The source revision, selected-file hashes, and adaptation boundaries are in
`~/.local/share/agent-skills/PROVENANCE.md`. Each package includes the original
MIT license. Updates are reviewed source changes, not floating downloads.

### Unslop

The three unslop skills remain available for normal model selection. Invoke one
directly by its native skill name, or use OpenCode's router:

```text
/unslop audit src/example.py
/unslop rewrite this paragraph: <text>
/unslop audit the UI in src/components
```

The router selects `unslop-code`, `unslop-text`, or `unslop-ui` from the target.
It defaults to an audit. It rewrites content or edits a file only when the
request explicitly asks for that action.

### Humanizer

Humanizer is explicit-only in every harness. Use the harness's native explicit
skill syntax, such as `/humanizer` in Claude Code and GitHub Copilot or
`$humanizer` in Codex. In OpenCode, use:

```text
/humanize <text>
/humanize edit docs/example.md
```

Every explicit humanization runs the preserved Humanizer procedure first and
`unslop-text` second. The adapter preserves facts, claims, code, commands,
paths, YAML metadata, and link targets. It edits a file only when the request
explicitly names the file and asks for an edit.

Humanizer's adapter carries all host-specific controls:

- Claude-compatible hosts: `disable-model-invocation: true`
- OpenCode V2: `metadata.opencode/autoinvoke: false`
- Codex: `policy.allow_implicit_invocation: false`

No implicit-invocation restrictions are added to the unslop skills, `handoff`,
or `chezmoi-dotfiles`.

## Provenance and pins

`handoff` and `chezmoi-dotfiles` are authored in this repository and have no
external pin. Maintenance references carry sanitized decisions and workflows;
private session data and local harness settings remain outside the public source.

| Skills | Audited upstream | Archive SHA-256 |
| --- | --- | --- |
| `unslop-code`, `unslop-text`, `unslop-ui` | [`JCarterJohnson/vibecoded-design-tells` at `f7c4aefc2c797a66e55b49354a93917ab60d33ac`](https://github.com/JCarterJohnson/vibecoded-design-tells/tree/f7c4aefc2c797a66e55b49354a93917ab60d33ac) | `22e20121c59cb4f3a72d0bcc1bf7df7a71ff09a0d32eb7d0f6fb5d181d7b8d9a` |
| `humanizer` | [`blader/humanizer` v3.0.0 at `9862685f575c65a8247f90369951df1b3416e3d6`](https://github.com/blader/humanizer/tree/9862685f575c65a8247f90369951df1b3416e3d6) | `4f4abbd690ba326fac501c991bd10e946283d4b3c8cdeccc0964aa244f9890ad` |

The archives contained 179 and 15 members respectively. The audit found no
absolute paths, parent traversal, links, or device entries. Each selected raw
file matched its archive member byte-for-byte.

Chezmoi fetches individual files from immutable commit URLs instead of fetching
the full archives. Every external has a fixed SHA-256 in
`home/.chezmoiexternal.toml`, has no refresh period or fallback URL, and lands
read-only. This avoids copying the research corpora or marketplace metadata into
the local cache.

Humanizer's original `SKILL.md`, `agents/openai.yaml`, and `LICENSE` remain
unchanged under `humanizer/upstream/`. The public adapter sits beside that
directory and owns only invocation, input handling, file-edit, and final-pass
policy.

### License boundaries

Both upstreams use the MIT License. The unslop repository states that its MIT
grant covers code and not harvested Reddit text. This integration installs the
published skill instructions, references, scanners, and license files only. It
does not copy the raw corpora, analysis datasets, charts, or collected comments.

Humanizer's MIT license is preserved at `humanizer/upstream/LICENSE`. Each
unslop skill carries the applicable upstream license file in its own canonical
directory.

### Update audit

1. Resolve the proposed public tag to a full commit.
2. Download the commit archive into an isolated temporary directory.
3. Reject absolute paths, parent traversal, links, and device entries.
4. Review the intended skill files and the license boundary.
5. Compare each immutable raw file with the matching archive member.
6. Recalculate the archive and per-file SHA-256 values.
7. Update the exact URLs, checksums, and provenance records together.
8. Run the offline focused tests and complete prek suite.

Do not replace a commit with a branch, moving tag, release-latest URL, package
registry tag, marketplace cache, or installer.

## Threat boundaries

- Runtime behavior is instruction-only. No server, CLI plugin, prompt hook,
  telemetry, model side call, or network client is installed.
- The upstream scanners are non-executable files. A host agent must choose to
  run them through its normal permission flow.
- No skill pre-approves shell or network tools.
- OpenCode commands contain no shell blocks. Their arguments are treated as
  untrusted data.
- Humanizer is unavailable to implicit model selection. Its file mode requires
  an explicit edit request for a named file.
- Unslop's OpenCode router defaults to a read-only audit.
- Handoff resume is read-only until the user says to continue. Save refuses
  secret-shaped values instead of writing them.
- Upstream asset downloads happen through chezmoi during external
  materialization. It accepts bytes only from the two exact public commit paths
  and verifies every file before writing it. First-party maintenance uses the
  host agent's normal tool permissions for the requested task.

## Validation

Focused validation is offline and does not fetch or install anything:

```zsh
python3 scripts/validate-agent-skills.py
python3 -m unittest tests/test_agent_skills.py
scripts/validate-templates.sh
```

The validator checks pins, checksums, every current AI sub-feature gate, per-skill
symlink targets, duplicate discovery roots, Humanizer invocation metadata,
command ordering, forbidden shell blocks, allowed URL hosts, and public-boundary
patterns. Tests also render the maintenance assets into a disposable home,
preserve unrelated skills, and exclude repository guidance from managed targets
and archives. The complete repository gate remains:

```zsh
prek run --all-files
```
