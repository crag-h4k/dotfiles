<!-- docs/agent-skills.md -->
# Cross-harness agent skills

## Table of Contents

- [Selection and layout](#selection-and-layout)
- [Harness support](#harness-support)
- [Invocation](#invocation)
  - [Unslop](#unslop)
  - [Humanizer](#humanizer)
- [Provenance and pins](#provenance-and-pins)
  - [License boundaries](#license-boundaries)
  - [Update audit](#update-audit)
- [Threat boundaries](#threat-boundaries)
- [Validation](#validation)

## Selection and layout

Writing-quality skills install automatically when any existing `ai` sub-feature
is selected. There is no separate picker or `writing_quality` flag. A host with
every `ai` sub-feature disabled gets none of these assets.

The only canonical copies live under `~/.local/share/agent-skills/`:

```text
~/.local/share/agent-skills/
├── PROVENANCE.md
├── humanizer/
├── unslop-code/
├── unslop-text/
└── unslop-ui/
```

Chezmoi creates one relative symlink per skill under both `~/.claude/skills/`
and `~/.agents/skills/`. It never replaces either skills directory. Existing
and future skills beside these four remain untouched.

## Harness support

| Harness | Discovery root | Notes |
| --- | --- | --- |
| Claude Code | `~/.claude/skills` | Native skill discovery; Humanizer uses `disable-model-invocation: true` |
| CodeCompanion | `~/.claude/skills` | Uses the Claude-compatible skill root |
| Codex | `~/.agents/skills` | Native skill discovery; Humanizer's `agents/openai.yaml` disables implicit invocation |
| OpenCode V2 | `~/.agents/skills` | Native compatibility root; also sees `.claude`, but both links resolve to the same canonical directory and one effective ID |
| GitHub Copilot | `~/.agents/skills` | Native personal skill discovery; Humanizer uses explicit-only frontmatter |

OpenCode commands live at `~/.config/opencode/commands/unslop.md` and
`~/.config/opencode/commands/humanize.md`. They are prompt-only Markdown with no
shell interpolation.

Other harnesses are unsupported. A future integration should warn and continue
rather than fail chezmoi apply or create a parallel skill copy.

## Invocation

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

No implicit-invocation restrictions are added to the unslop skills.

## Provenance and pins

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
8. Run the offline focused tests and complete pre-commit suite.

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
- For these skills, only chezmoi uses the network, during external
  materialization. It accepts bytes only from the two exact public commit paths
  and verifies every file before writing it.

## Validation

Focused validation is offline and does not fetch or install anything:

```zsh
python3 scripts/validate-agent-skills.py
python3 -m unittest tests/test_agent_skills.py
scripts/validate-templates.sh
```

The validator checks pins, checksums, all seven AI sub-feature gates, per-skill
symlink targets, duplicate discovery roots, Humanizer invocation metadata,
command ordering, forbidden shell blocks, allowed URL hosts, and public-boundary
patterns. The complete repository gate remains:

```zsh
pre-commit run --all-files
```
