<!-- $HOME/.local/share/agent-skills/PROVENANCE.md -->
# Agent skill provenance

## Table of Contents

- [Installed sources](#installed-sources)
- [Included boundaries](#included-boundaries)
- [Update audit](#update-audit)

## Installed sources

| Skills | Upstream revision | Archive SHA-256 | License |
| --- | --- | --- | --- |
| `unslop-code`, `unslop-text`, `unslop-ui` | `JCarterJohnson/vibecoded-design-tells` commit `f7c4aefc2c797a66e55b49354a93917ab60d33ac` | `22e20121c59cb4f3a72d0bcc1bf7df7a71ff09a0d32eb7d0f6fb5d181d7b8d9a` | MIT for code and associated skill files; upstream excludes harvested text from that grant |
| `humanizer` | `blader/humanizer` v3.0.0, commit `9862685f575c65a8247f90369951df1b3416e3d6` | `4f4abbd690ba326fac501c991bd10e946283d4b3c8cdeccc0964aa244f9890ad` | MIT |

Each fetched file has its own SHA-256 in
`home/.chezmoiexternal.toml`. Humanizer's original `SKILL.md`,
`agents/openai.yaml`, and license remain unchanged under `humanizer/upstream/`.
The adjacent adapter adds cross-harness invocation policy without altering the
upstream files. `handoff` and `chezmoi-dotfiles` are authored in this repository
and have no upstream pin. The maintenance skill adapts earlier private guidance
to current public repository behavior. Its decisions reference records sanitized
evidence; private transcripts, account configuration, and employer material are
excluded. It installs read-only with the other canonical skills.

Selecting `ai > openviking` also installs `openviking-memory`,
`openviking-skills`, and `ov-experience-memory`. Their immutable source is
`volcengine/OpenViking` commit `9b9ac101f1c47a62c050a7d7bb372c6f36266302`,
matching the published `@openviking/opencode-plugin@2026.10.7` skill bytes.
The npm archive's SHA-512 integrity was verified, its 44 members were inspected
for unsafe paths and links, and each selected raw file matched its package
member. Per-file SHA-256 checksums are in the external manifest.

These three instructions remain unmodified. The npm plugin declares
Apache-2.0; the separate OpenViking server package declares the GNU Affero
General Public License version 3.
Native discovery links point at one canonical copy per skill. They install
only with the OpenViking component and do not configure a connection or grant
tool permissions themselves.

`openviking-cleanup` is an additional first-party review workflow, authored in
this repository without an upstream pin. It follows the same OpenViking-only
gate and compatibility links. It uses existing memory tools for read-only
auditing, batched decisions, and approved changes; it adds no plugin or CLI and
does not run automatic in-place consolidation as a preview.

## Included boundaries

The store includes only the distributable skill instructions, references,
read-only scanner scripts, and license files. It excludes raw research corpora,
analysis datasets, charts, repository automation, packaged marketplace files,
and plugin manifests.

The scanner scripts are regular non-executable files. The skills do not install
servers, CLI plugins, hooks, telemetry, network clients, or tool dependencies.

## Update audit

1. Resolve an exact public tag or commit.
2. Download its commit archive into an isolated temporary directory.
3. Reject absolute paths, parent traversal, links, and device entries.
4. Review the intended skill files and applicable license boundary.
5. Compare each immutable raw file byte-for-byte with the archive member.
6. Recalculate the archive and per-file SHA-256 values.
7. Update the exact URLs, checksums, and this provenance record together.
8. Run the offline skill validation and the complete prek suite.

Normal tests never fetch dependencies. A checksum mismatch stops chezmoi before
the changed file reaches the canonical store.
