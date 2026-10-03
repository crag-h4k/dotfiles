#!/usr/bin/env python3
"""Merge portable OpenCode rules without replacing private global instructions."""

import sys

START = "<!-- dotfiles:question-tool:start -->"
END = "<!-- dotfiles:question-tool:end -->"
BLOCK = f"""{START}
When asking me how to proceed or how to evaluate options, use OpenCode's
`question` tool to present the choices instead of asking only in plain chat.
Before any mutating Git operation (including add, commit, push, rm, reset,
clean, checkout, restore, and worktree changes), use `question` to get my
explicit authorization for that operation. Read-only Git operations are fine.
Before a commit, present at least two candidate commit messages that follow
this repo's Release Please Conventional Commit conventions, then ask me to
choose one with `question`. Permission prompts do not replace this decision.
{END}"""

existing = sys.stdin.read()
if START in existing or END in existing:
    if existing.count(START) != 1 or existing.count(END) != 1:
        sys.exit("Ambiguous managed question-tool block in global AGENTS.md")
    start = existing.index(START)
    end = existing.index(END) + len(END)
    if start >= end:
        sys.exit("Out-of-order managed question-tool block in global AGENTS.md")
    sys.stdout.write(existing[:start] + BLOCK + existing[end:])
else:
    sys.stdout.write(existing.rstrip("\n") + ("\n\n" if existing else "") + BLOCK + "\n")
