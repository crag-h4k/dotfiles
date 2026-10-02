# Packaging and authoring scripts

Read `docs/architecture.md`, `docs/operation.md`, and the maintenance skill's
workflows reference for changes to planning, installation, backup, or recovery.

## Package transactions

- Keep package declarations and resolution shared by the preview and installer.
  Show installed and candidate versions/revisions, source, status, and component
  origins. Deduplicate records while preserving their origins.
- One package run refreshes the relevant metadata, resolves the plan, and asks
  for one approval. Install the approved candidates; do not resolve a different
  latest release after the user approves. Current packages should skip work.
- Preserve configs-only behavior, a default-no confirmation, and the explicit
  unattended opt-in. Declining one run must not rewrite persisted installMode.
  Package updates also require the existing update trigger.
- Batch selected Homebrew/APT operations. Bootstrap dependencies may precede the
  batch when the remaining operations require them. Avoid repeated manager
  refreshes and one installation call per component.
- Report unknown/unresolved candidates honestly. Do not label every floating
  dependency an update or infer installation success from a transaction marker.
- Existing Git externals need cleanliness and safe fast-forward checks before
  updates. Skill externals retain immutable URLs and per-file checksums.

## Portability and feedback

- Preserve macOS Bash 3.2 compatibility in Bash installers. Shared notifier
  shell code is POSIX and array-free; Zsh-specific code stays in Zsh files.
- Prefer Debian Trixie's native packages where that is the declared policy.
  Detect APT repositories by their configured URI/suite, including legacy entries
  and alternate valid keyrings. New sources use signed Deb822 `.sources` files.
  Do not blindly add duplicate sources or remove unrelated configuration.
- Check flags against the actual supported tool versions. Keep Gum's terminal
  input available when it queries a TTY. Preserve typed and unattended paths;
  terminal response bytes must not leak into result output.
- Print phase starts/completions and keep manager logs visible. Preserve the
  private install log and `install.sh --log` interface. Diagnose long silent
  phases with timing instead of hiding command output behind another spinner.

## Activation and failure

Stage complete release trees, verify downloads and required modules, and run
bounded health checks before switching stable pointers or launchers. Keep the
previous working release recoverable. Do not overlay files into a live runtime
or remove an existing package before its replacement passes validation.

Keep file ownership and user-local installation correct for the target account,
including externally run root installs. Do not execute privileged operations as
an agent. Independent package operations may continue after a failure, but the
final aggregate result must report that failure.

Authoring generators must remain separate from installation. Update their
committed output when the inputs change and use their check mode in validation.
