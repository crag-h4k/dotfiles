<!-- docs/gitleaks.md -->
# Gitleaks

Gitleaks has two jobs here: warn early in Neovim and enforce before a secret
reaches Git history. The editor is helpful; pre-commit is the bouncer.

## Neovim warnings

Mason installs Gitleaks because this executable exists for the editor
integration. Normal file buffers are scanned asynchronously after read and
save.

Findings appear as warning diagnostics. Scans run in the background and never
block reads or saves.

The integration:

- cancels an older scan when the same buffer changes again;
- treats exit code `1` as findings rather than an execution failure;
- redacts the CLI report;
- omits the matched secret and source line from diagnostics;
- leaves the last good result intact when Gitleaks itself fails.

If Mason is still installing Gitleaks, the buffer remains usable and a later
read or save tries again.

## Managed exclusions

The editor skips special buffers and paths that are mostly dependency or
generated noise:

- `.git/`
- `.terraform/`
- `.cache/`
- `node_modules/`
- `vendor/`
- help, terminal, quickfix, Oil, Lazy, and Mason buffers

These are path and filetype exclusions, not blanket content allowlists. Keep
actual detector exceptions explicit.

## Project policy

When a project-root `.gitleaks.toml` exists, Neovim passes it to Gitleaks
explicitly and runs from that root. Project allowlists therefore apply to the
same file paths the developer sees.

A project that wants the upstream rules plus local exceptions can start with:

```toml
[extend]
useDefault = true

[[allowlists]]
description = "Known generated fixture"
paths = [
  '''^tests/fixtures/generated/''',
]
```

Keep allowlists narrow and reviewable. Disabling a detector because one fixture
annoyed you is how the next real credential gets a free ride.

The dotfiles repository uses `config/linters/gitleaks.toml`. Its allowlists
cover vendored upstream content and committed binary media, while the default
Gitleaks rules remain enabled.

## Pre-commit enforcement

The official pinned hook scans staged content with redaction:

```sh
pre-commit run gitleaks --all-files
```

Unlike the Neovim integration, a finding here fails the check. That boundary is
intentional: saving work should stay fast, but committing a credential should
become somebody's problem immediately.

The hook configuration lives in `.pre-commit-config.yaml`; repository policy
lives in `config/linters/gitleaks.toml`.

## Troubleshooting

Check the Mason package and executable first:

```vim
:Mason
```

```sh
command -v gitleaks
gitleaks version
```

Run the project policy directly when editor and pre-commit results disagree:

```sh
gitleaks dir --redact --config .gitleaks.toml .
```

Use `config/linters/gitleaks.toml` instead when testing this repository.
