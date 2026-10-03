# Agent guidance

The root [AGENTS.md](../AGENTS.md) describes how to work on this repository.
Its linked child files cover managed source, packaging, tests, CI, documentation,
OpenCode2, Neovim, and notifications. Read the relevant chain before editing even
when the harness starts at the repository root.

Guidance is based on explicit user decisions, recurring corrections, and current
code. Supported inferences are defaults. Keep entrypoints concise and update
affected guidance with behavior changes. Repository contracts under `home/` are
excluded from deployment. The managed OpenCode global `AGENTS.md` is separate
and contains only portable user preferences.

## Maintenance skill

The [chezmoi-dotfiles source skill](../home/dot_local/share/agent-skills/chezmoi-dotfiles/readonly_SKILL.md)
contains the maintenance workflow. Its
[workflows reference](../home/dot_local/share/agent-skills/chezmoi-dotfiles/references/readonly_workflows.md)
covers component changes, package failures, terminal diagnosis, and deployment.
The [decisions reference](../home/dot_local/share/agent-skills/chezmoi-dotfiles/references/readonly_decisions.md)
records sanitized evidence and superseded assumptions.

The skill installs through the existing shared AI asset gate. It is authored in
this repository and normally available to model selection. OpenCode2 is the
primary audience; Claude, Codex, CodeCompanion, and Copilot share its canonical
copy through the existing per-skill compatibility links.

After a normal deployment, OpenCode supports:

```text
/dotfiles
/dotfiles diagnose a repeated package update
/dotfiles refresh-guidance
```

An empty command reports orientation. A task follows its authorized scope;
`refresh-guidance` explicitly reviews history. Routine maintenance does not scan
all chats. The command contains no shell interpolation or permission grants.

A source-only change does not replace installed skills or modify private harness
configuration. Read the source skill directly until the next normal apply. If an
installed copy is stale, compare its manifest with this checkout and inspect
discovery roots before changing an unrelated skill or private configuration.

## Validation

The offline shared-skill checks cover the public authored files, exact upstream
pins, selection gates, canonical assets, per-skill links, and command safety:

```sh
python3 scripts/validate-agent-skills.py
python3 -m unittest tests/test_agent_skills.py
prek run bats-source-layout --all-files
prek run --all-files
```

Tests render the maintenance skill into a disposable destination, verify its
references and link targets, and preserve an unrelated local skill. They also
check that repository contracts are absent from managed targets and archives;
only the OpenCode global instructions are deployed when selected.
The complete deployment gate remains unchanged; see [CI](ci.md).
