<!-- docs/ci.md -->
# CI

Pull requests and pushes to `main` use one workflow. The quick checks and all
deployment targets run in parallel, because proving a dotfiles change should
not require a coffee break and a small ritual.

## Table of Contents

- [Pull request metadata](#pull-request-metadata)
- [prek](#prek)
- [Trixie deployment](#trixie-deployment)
- [macOS deployment](#macos-deployment)
- [pbvar tests](#pbvar-tests)
- [Parallel jobs and summaries](#parallel-jobs-and-summaries)
- [Required repository rules](#required-repository-rules)
- [Running checks locally](#running-checks-locally)

## Pull request metadata

The `PR metadata` job checks the source branch and squash-merge title before
Release Please ever sees the commit.

| Branch | Required title type |
| --- | --- |
| `feat/*` | `feat` |
| `fix/*`, `hotfix/*` | `fix` |
| `deps/*` | `deps` |
| `docs/*` | `docs` |
| `chore/*` | `chore` |
| `ci/*` | `ci` |
| `refactor/*` | `refactor` |

Scopes and breaking markers are supported:

```text
feat(ci): add native macOS deployment
fix(tmux): restore wheel scrolling
feat(components)!: replace the component schema
```

Release Please and recognized dependency-bot branches are exempt. Everything
else must use the mapping; “update-stuff-final-2” can remain a local memory.

The validator lives in `scripts/validate-pr-metadata.sh` and has Bats coverage
in `tests/test_pr_metadata.bats`.

## prek

The reusable `.github/workflows/prek.yaml` workflow pins prek to the same
version documented in [Contributing](../CONTRIBUTING.md) and runs
`.pre-commit-config.yaml`, the hook set used for local commits:

- secret scanning;
- file-format and executable checks;
- ShellCheck and actionlint;
- Markdown, Lua, and template validation;
- palette drift checks;
- Python and Bats suites.

The full hook set runs on native Linux x86-64 (`ubuntu-24.04`). The job asserts
its machine architecture. ARM64 coverage stays in the Trixie and macOS
deployment jobs, not in a second copy of the same prek hooks.

The workflow checks out the palette submodule and installs the system
dependencies needed by hooks. Bats is pinned in the hooks' isolated Node
environment, so local runs and CI use the same runner without a global Bats
installation. The workflow caches `~/.cache/prek` by operating system,
architecture, prek version, and hook configuration. The shared CI summary
comment includes the combined prek result. The prek and LuaRocks caches include
the runner architecture, so native artifacts never cross between runners.

## Trixie deployment

Two Trixie jobs call `.github/workflows/trixie-deployment.yaml`: x86-64 on
`ubuntu-24.04`, and ARM64 on `ubuntu-24.04-arm`. Each builds
`tests/trixie-deployment/Dockerfile.trixie`, then runs a real unattended
package-mode chezmoi apply as a non-root user.

Python is a bootstrap prerequisite: selected configuration merge programs run
before the post-apply package hook. The Trixie image includes it alongside Git,
curl, and chezmoi so OpenCode configuration can be applied before its packages
are installed.

The host machine, Docker platform, and built image architecture must agree.
These are native runs, not QEMU emulation. Separate reusable-workflow calls keep
each architecture's build, install, and smoke outputs distinct; one result
cannot overwrite the other as a matrix output might.

The deployment deliberately starts with an existing GitHub CLI APT source using
an alternate valid keyring path. That catches duplicate-repository and
conflicting `Signed-By` regressions before they reach a workstation.

The focused component set installs Zsh, tmux, shared Git configuration, and
OpenCode, its disabled MCP runtimes, and the isolated OpenViking runtime.
Trixie's `tmux` comes from Debian APT: no source build, no mystery binary.

After install, the shared smoke test checks the managed files, shell runtime,
Git behavior, tmux options, dynamic scrollback, and wheel binding.
OpenViking runs with disposable private configuration and no provider login.
Its smoke test starts the native server, verifies loopback readiness, rejects
unauthenticated data access, and provisions a separate USER credential. It does
not start a persistent user service, download Ollama models, or validate remote
provider quality.

## macOS deployment

The macOS job runs natively on the ARM64 `macos-15` image. Runner preparation
rejects Intel machines before Homebrew work begins. The labels follow GitHub's
[hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

The disposable runner's Homebrew setup can leave a manual `bin/openssl` symlink
to `opt/openssl@1.1/bin/openssl`. Preparation unlinks the retired keg first.
If Homebrew leaves that exact symlink behind, the helper rechecks its target
and removes only the symlink, allowing OpenSSL 3 dependencies to link normally.
Regular files, other targets, and the retired keg's files remain untouched.
It does not uninstall packages or use force-overwrite. The helper refuses to
run outside GitHub Actions and also removes the runner's unused, untrusted `aws/tap`.

The build phase copies a clean source tree and verifies the rendered archive.
The install phase performs a fully headless package-mode apply with Homebrew.
The same runtime smoke script then checks Zsh, Git, tmux, and the native
OpenViking runtime with isolated private state.

Build, install, and smoke outcomes are exported separately so a failure says
which layer broke.

## pbvar tests

The separate `pbvar-build` workflow runs Go formatting, vet, and tests natively
on Linux x86-64, Linux ARM64, and macOS ARM64. It runs when the tool or its
workflow changes. Architecture assertions and disabled fail-fast preserve
coverage of every target. Release cross-compilation remains a separate Linux
job and waits for every native test entry to pass.

## Parallel jobs and summaries

Both Trixie architectures, ARM64 macOS, prek, and PR metadata are sibling jobs.
GitHub can schedule them together instead of serializing operating systems.

The deployment summary job posts one sticky table with build, install, and
smoke outcomes separately for Linux x86-64, Linux ARM64, and macOS ARM64. The
aggregate `CI` job fails unless both Linux deployments, macOS, and prek succeed.
It also enforces PR metadata on pull requests.

On pushes to `main`, PR metadata is expected to be skipped. The other checks
still run before Release Please is allowed to update or publish anything.

## Required repository rules

The `main` ruleset should require:

- pull requests;
- squash merges and linear history;
- `CI`;
- `PR metadata`;
- successful full prek checks on Linux x86-64;
- successful Trixie deployments on both Linux architectures;
- successful ARM64 macOS deployment.

The stable `CI` check enforces all architecture-specific jobs. Architecture
names can change individual check contexts; review any separately required
checks against the actual run before changing repository rules.

GitHub environment names and check names are case-sensitive enough to waste an
afternoon. Copy them from the completed workflow when configuring the ruleset.

## Running checks locally

Use focused tests while iterating:

```sh
prek run bats-pr-metadata --all-files
prek run bats-ci-summary --all-files
prek run actionlint --all-files
```

Run applicable hooks against the changed files before review. This includes
staged and unstaged changes relative to local `main`; stage new files first:

```sh
python3 scripts/prek-changed.py
```

CI keeps `prek run --all-files` so unrelated files still get checked before
merge.

The macOS job needs a macOS runner. The Trixie deployment can be reproduced
with the documented Dockerfile, but ordinary development should not need to
reinstall half a workstation after every typo.
