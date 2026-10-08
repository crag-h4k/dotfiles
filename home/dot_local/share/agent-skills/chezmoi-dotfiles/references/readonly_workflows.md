# Maintenance workflows

Resolve the repository root first. Paths below are relative to it. Read its
AGENTS.md and the relevant child guidance; these procedures supplement them.

## Component or configuration changes

Inspect the declaration in `home/.chezmoi.toml.tmpl` and trace its resolved
component keys through file/external gates, install flags, package records, and
the render matrix. Update the layers the change actually affects. File-only
features do not need invented package flags. Test both selected and unselected
paths and preserve saved choices on re-init.

Use `modify_` programs for supported configuration merges. Test unrelated user
keys and comments against realistic input. For a locally changed target, compare
source, rendered output, and the override mechanism in `docs/operation.md` before
choosing overwrite. Private CLI permissions and server routing stay in overlays.

For skill additions, keep one canonical copy under
`home/dot_local/share/agent-skills` and per-entry links under the existing harness
roots. Update gates, provenance, the exact validator file sets, docs, and tests
together. Third-party bytes require the existing immutable pin/checksum audit;
first-party skills are authored source. Preserve independent local/work skills.

## Package plan or installation failures

Inspect the private install log through the existing `install.sh --log` interface
without pasting raw logs into public artifacts. Identify the failed phase,
account, component selections, installed version, candidate, and actual command.
Check the same account and hook environment that reported the failure.

Trace records from `scripts/package-plan.sh` and `scripts/package-resolve.sh`
into `scripts/install.sh` and the component installer. Verify that installation
consumes the approved candidate. A rerun should recognize current versions and
skip their work; unresolved versions must remain distinguishable from updates.
Every package-mode apply checks the selected package set, including source
updates, explicit external refreshes, and init/apply with unchanged selections.
For Debian Node/npm failures, check the NodeSource bootstrap before the main
APT batch and verify both binaries; Debian's nodejs-only package is insufficient.
Check actual binaries/package records instead of assuming a cache stamp proves
success. Keep native managers, release assets, Git externals, and Neovim-owned
packages visible at the detail level needed to approve the transaction.

For APT conflicts, inspect configured repository URIs, suites, and signing-key
paths across `.sources` and legacy entries. Reuse valid existing configuration.
Do not add a duplicate source or remove one simply because its filename differs.
Any privileged repair is handed to the user under the active host policy.

For release failures, inspect the staged tree, wrapper argument forwarding,
health-check deadline, required imports, and stable pointer. Repair or roll back
the failed transition while retaining the previous working release. Respect
target ownership when another account uses a shared source checkout.

## Terminal and editor regressions

Record the chain: terminal/client, SSH, tmux or direct session, application, and
versions. Compare the failing chain with a working path. Check glyph width,
truecolor, capability probes, raw reply bytes, bindings, and parser availability.
Use OpenCode's existing `/demo diagnostics` for footer display; preserve its
minimal model usage. Font changes alone do not settle rendering failures.

For tmux, test a separate socket and verify fresh-server configuration loading,
scrolling, selection, notification firing, and clearing. Preserve active sessions.
For Neovim, inspect the real plugin branch/API and distinguish shell tools from
Mason/Lazy-managed packages. Startup provisions missing items; approved package
mode performs version changes. Use an isolated home/data tree for verification.

## Validation and deployment

Choose a focused hook from `.pre-commit-config.yaml`, then run the full gate:

```sh
prek run --all-files
```

Bats runs through the pinned prek environment. Skill/source-layout changes also
need the offline shared-skill tests, template rendering, and managed-target
checks. Do not turn a missing global bats binary into an installer dependency.

Use the controlled deployment fixtures for package-mode tests. Both macOS and
Trixie must complete build, unattended installation, and runtime smoke checks.
Ordinary tests must use disposable paths and package stubs. Do not run the real
home's package-mode apply repeatedly to reproduce a test.

For a requested worktree deployment, use the repository root with
`chezmoi --source`, inspect the rendered diff and backup/recovery path, then apply
only the authorized mode. A repository-only request ends after source changes
and validation. Do not activate a skill or restart a shared server as a side
effect of preparing that source change.

## Keep guidance current

When behavior changes, update the affected product doc and the nearest durable
rule. Keep the root concise and load references only for relevant work. A broader
refresh is explicit: review available evidence, reconcile it with the current
checkout, remove obsolete assumptions, and record the basis for changed defaults.
Report evidence gaps instead of claiming to have read inaccessible chat archives.
