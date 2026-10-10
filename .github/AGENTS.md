# CI, pull requests, and releases

Read `CONTRIBUTING.md`, `docs/ci.md`, and `docs/releases.md` from the repo root.

- Preserve the complete `prek run --all-files` gate and macOS/Trixie deployment
  matrix. Changed-file filtering has produced gaps in local-hook coverage; do
  not make it the merge gate. Prefer caching, shared setup, and parallel jobs.
- Build, install, and runtime smoke outcomes remain separately visible. Native
  ARM64 macOS and native x86-64/ARM64 containerized Trixie jobs run unattended in
  parallel. Full prek checks run on Linux x86-64. Trixie uses
  the distribution's tmux package and the alternate-keyring APT fixture.
- Keep the aggregate CI result accurate for failures and expected skips. PR-only
  metadata skips on main pushes must not suppress successful release processing.
  Retain separate deployment outputs for each architecture; one matrix entry
  must not overwrite another entry's build/install/smoke results.
- Update existing sticky result comments. Preserve their build/install/smoke
  detail and avoid accumulating a new comment on every run.
- Keep Conventional Commit PR titles aligned with branch prefixes. Main uses
  squash merges and linear history. Branch names alone do not determine releases.
- Release Please collects changes into a pending release PR. Publication happens
  when that PR is deliberately merged. Preserve SemVer and the release guard.
- CHANGELOG and release manifests belong to the release workflow. Do not repair
  generated formatting by hand or publish a tag as a side effect of a feature.
- Keep CI support files beneath the existing project infrastructure directories.
  Avoid adding unrelated automation clutter to the repository root.

This guidance does not authorize GitHub writes, commits, pushes, merges, changes
to protection rules, or releases. Complete the concrete change and validation
before requesting any approval required by the current task.
