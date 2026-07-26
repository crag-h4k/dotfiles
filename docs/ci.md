<!-- docs/ci.md -->
# CI

Pull requests and pushes to `main` use one workflow. The quick checks and both
deployment targets run in parallel, because proving a dotfiles change should
not require a coffee break and a small ritual.

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

## Pre-commit

The reusable pre-commit workflow runs the same hook set as local development:

- secret scanning;
- file-format and executable checks;
- ShellCheck and actionlint;
- Markdown, Lua, and template validation;
- palette drift checks;
- Python and Bats suites.

The workflow checks out the palette submodule and installs only the system
dependencies needed by hooks. Its sticky PR comment summarizes the hook
outcomes without dumping a novel into the conversation.

## Trixie deployment

The Trixie job builds `tests/trixie-deployment/Dockerfile.trixie`, then runs a
real unattended package-mode chezmoi apply as a non-root user.

The deployment deliberately starts with an existing GitHub CLI APT source using
an alternate valid keyring path. That catches duplicate-repository and
conflicting `Signed-By` regressions before they reach a workstation.

The focused component set installs Zsh, tmux, and shared Git configuration.
Trixie's `tmux` comes from Debian APT—no source build, no mystery binary.

After install, the shared smoke test checks the managed files, shell runtime,
Git behavior, tmux options, dynamic scrollback, and wheel binding.

## macOS deployment

The macOS job runs natively on `macos-15`; it is not a Linux container wearing
an Apple sticker.

The build phase copies a clean source tree and verifies the rendered archive.
The install phase performs a fully headless package-mode apply with Homebrew.
The same runtime smoke script then checks Zsh, Git, and tmux.

Build, install, and smoke outcomes are exported separately so a failure says
which layer broke.

## Parallel jobs and summaries

Trixie, macOS, pre-commit, and PR metadata are sibling jobs. GitHub can schedule
them together instead of serializing two operating systems for no good reason.

The deployment summary job posts one sticky table with build, install, and
smoke outcomes for both platforms. The aggregate `CI` job fails unless every
required sibling succeeds.

On pushes to `main`, PR metadata is expected to be skipped. The other checks
still run before Release Please is allowed to update or publish anything.

## Required repository rules

The `main` ruleset should require:

- pull requests;
- squash merges and linear history;
- `CI`;
- `PR metadata`;
- successful `trixie` deployment;
- successful `macos` deployment.

GitHub environment names and check names are case-sensitive enough to waste an
afternoon. Copy them from the completed workflow when configuring the ruleset.

## Running checks locally

Use focused tests while iterating:

```sh
bats tests/test_pr_metadata.bats
bats tests/test_ci_summary.bats
pre-commit run actionlint --all-files
```

Run the full local gate before review:

```sh
pre-commit run --all-files
```

The macOS job needs a macOS runner. The Trixie deployment can be reproduced
with the documented Dockerfile, but ordinary development should not need to
reinstall half a workstation after every typo.
