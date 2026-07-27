<!-- docs/releases.md -->
# Releases

Release Please collects changes on `main` and maintains a release PR. Merging a
feature PR updates that proposal; it does not immediately mint another tag.

The release exists only when somebody deliberately merges the release PR.

## What triggers a release proposal

Release Please parses Conventional Commit messages on `main`:

| Type | SemVer effect |
| --- | --- |
| `fix` | patch |
| `feat` | minor |
| `feat!`, `fix!`, or a `BREAKING CHANGE` footer | major |
| `deps`, `docs`, `chore`, `ci`, `refactor` | no release by themselves |

This repository uses standard SemVer behavior. A feature below `1.0.0` bumps the
minor version; it is not forced into another `0.0.x` patch.

GitHub squash-merges pull requests, so the PR title becomes the commit title
Release Please parses. The `PR metadata` job keeps branch and title types
aligned before merge.

Branch names alone never trigger Release Please.

## The release PR

After the stable `CI` gate passes on a push to `main`, the Release Please action:

1. reads commits since the latest release;
1. creates or updates its pending release PR;
1. updates `CHANGELOG.md` and the version manifest in that PR.

The action uses the dedicated `RELEASE_PLEASE_TOKEN`. A fine-grained token lets
the generated PR trigger the same required CI as a human-authored PR.

The job guards on `always() && needs.ci.result == 'success'`. The `CI` gate fans
in over the PR-only `pr-metadata` job, which is skipped on a push. A plain `if:`
would let that skipped sibling propagate down the `needs` chain and skip Release
Please even on a green `main` push, so the `always()` form is required.

Its repository permissions are:

- Contents: read/write
- Pull requests: read/write
- Issues: read/write

Merging the release PR causes the next run to create the version tag and GitHub
Release. Ordinary feature merges cannot publish by themselves.

## Conventional titles

Good squash titles:

```text
feat(ci): add headless macOS deployment
fix(apt): reuse an existing GitHub CLI source
docs(releases): explain intentional publishing
```

An unparseable title is ignored rather than guessed. Release Please is
correctly cautious and spectacularly unhelpful about casual prose.

## Repairing a missed commit

For a squash-merged PR with the wrong title, add this block to the merged PR
body:

```text
BEGIN_COMMIT_OVERRIDE
feat(ci): add headless macOS and Trixie deployment validation
END_COMMIT_OVERRIDE
```

The next Release Please run uses the override as that merge's commit message.
Do not use this with plain merge commits; the project uses squash merges for
this reason.

## The v1.0.0 release

Feature 6 is the planned `v1.0.0` release candidate. Its PR remains a normal
`feat(repo): ...` change, with an explicit release footer in the squash commit:

```text
feat(repo): document and enforce the workstation workflow

Release-As: 1.0.0
```

The same instruction can be supplied through a commit override in the PR body:

```text
BEGIN_COMMIT_OVERRIDE
feat(repo): document and enforce the workstation workflow

Release-As: 1.0.0
END_COMMIT_OVERRIDE
```

Use one mechanism, not both. After that feature merges, review the generated
release PR and merge it only when `v1.0.0` is genuinely ready.

No sticky `release-as` value belongs in the repository config. Leaving one
there would keep trying to force later releases to the same version, which is
the sort of automation joke this repo is trying not to become.
