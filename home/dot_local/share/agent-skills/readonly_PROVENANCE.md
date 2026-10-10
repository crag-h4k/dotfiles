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
| `git-publish`, `pr-watch`, `git-worktree` | Adapted from `EveryInc/compound-engineering-plugin` commit `51aa537383744736eb8ad30468d34420e9fb8ea8` | `9f7e77976ff8abb54ca58d5f2b851e95b69e1a9e5701efb762897dd7dc263455` | MIT, copyright 2025 Every |

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

## Included boundaries

The three Git workflows are maintained local adaptations, not automatically
refreshed upstream externals. Each package carries Every's original MIT notice.
Source review used these exact files at the pinned revision:

| Source | SHA-256 |
| --- | --- |
| `LICENSE` | `61d89de7646effdaba2d0a4ab7bd0eba60b4094b83efe5bc73c7940e43e93fc6` |
| `skills/ce-commit-push-pr/SKILL.md` | `deb35ce03204b9c4c372c9c82a8f68e34d00fa800e1fc92a3642811ab43d1591` |
| `skills/ce-commit-push-pr/references/commit-and-push.md` | `b4b3857cdc55edbbcd3f46a8635946a08eb0ad9c6fb6b3406ddf0f193b56c597` |
| `skills/ce-commit-push-pr/references/apply-and-handoff.md` | `f35d2392c3b5fa0e150f5fa1a85dbb92855610051e67425ad8f4ec6ebd72b020` |
| `skills/ce-babysit-pr/SKILL.md` | `7e5769d01dc4b451382a970c0fd5ba3cc1f1b3134521a4fd138ddc1788bf84e7` |
| `skills/ce-worktree/SKILL.md` | `832f90ee9bb7c5686617015d587cc2d4fd2482a40127da104fe3165bcb3121cb` |

The archive was inspected without extraction. Its eight non-regular members
were excluded; each selected regular file matched its immutable raw URL.
No upstream executable, helper, plugin manifest, or autonomous workflow is
installed. The adaptations replace implicit write authority and pipeline mode
with blocking approvals, read-only monitoring, and existing worktree ownership.
Descriptions and routers introduce no dependency on OpenChamber.

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
