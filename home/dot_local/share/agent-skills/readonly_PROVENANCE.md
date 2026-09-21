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
upstream files.

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
8. Run the offline skill validation and the complete pre-commit suite.

Normal tests never fetch dependencies. A checksum mismatch stops chezmoi before
the changed file reaches the canonical store.
