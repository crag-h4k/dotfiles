# Contributing

This is a personal workstation repo, not a standards committee. The rules are
here so the next change is easy to review and Release Please does not stare at
an unparseable squash commit and quietly wander off.

## Branches and pull requests

Start from current `main` and use a worktree:

```sh
git fetch origin
git worktree add -b feat/short-description \
  ../dotfiles-short-description origin/main
cd ../dotfiles-short-description
```

A worktree is a normal branch with another checkout. `git status`, `git diff`,
`git add`, `git commit`, and `git push -u origin HEAD` behave exactly as they do
anywhere else.

Branch prefixes map to Conventional Commit PR titles:

| Branch | PR title |
| --- | --- |
| `feat/*` | `feat(scope): description` |
| `fix/*`, `hotfix/*` | `fix(scope): description` |
| `deps/*` | `deps(scope): description` |
| `docs/*` | `docs(scope): description` |
| `chore/*` | `chore(scope): description` |
| `ci/*` | `ci(scope): description` |
| `refactor/*` | `refactor(scope): description` |

Scopes are optional. Breaking changes use `!`, for example
`feat(components)!: replace the component schema`.

CI checks the branch/title pair because GitHub uses the PR title for the squash
commit on `main`. Release Please parses that commit; branch names feed the PR
metadata check.

Release Please and dependency-bot branches are exempt from the branch mapping.

## Editing and applying

For ordinary edits in the main chezmoi source:

```sh
chezmoi edit --apply ~/.zshrc
```

That edits the source file and applies the rendered target in one command. It
keeps the source tree in charge, which is the whole point of using chezmoi.

Inside a feature worktree, edit repository files normally and tell chezmoi to
use that checkout:

```sh
cd /path/to/dotfiles-worktree
$EDITOR home/dot_zshrc
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

The repository-level `.chezmoiroot` redirects chezmoi into `home/`. Do not pass
`home/` as the source yourself or chezmoi will miss the project root and its
special files.

Use a throwaway destination or the deployment tests when a change should not
touch the current host.

## Tests

Run the smallest relevant test while iterating:

```sh
bats tests/test_pr_metadata.bats
bats tests/test_tmux_startup.bats
shellcheck scripts/validate-pr-metadata.sh
```

Before review, run the same complete gate as CI:

```sh
pre-commit run --all-files
```

Pull requests also run native macOS and containerized Debian Trixie
deployments. Both are unattended package-mode installs followed by runtime
smoke tests; there is no button for “a human would probably fix this.”

## Merging and releases

`main` uses squash merges and linear history. Keep the PR title conventional,
then merge only after the required CI and deployment checks pass.

An ordinary merge does not publish a release. Release Please updates its
pending release PR, and a release appears only when that PR is deliberately
merged.

See [Release workflow](docs/releases.md) for SemVer rules, commit overrides, and
the one-time `v1.0.0` release instructions.

## Scope

Keep managed host state under `home/`. Project tests, scripts, docs, CI, linter
policy, and vendored authoring inputs stay outside the managed source root.

There is intentionally no license attached to this repository.
