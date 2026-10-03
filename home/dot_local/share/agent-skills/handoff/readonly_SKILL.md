---
name: handoff
description: Save, resume, integrate, list, or close a session handoff. Use when the user asks to hand off, pick up or incorporate a handoff into the current session, list handoffs, or close one. An incidental use of the word is not a save.
user-invocable: true
argument-hint: "[save|resume|integrate|list|close] [project-or-slug]"
---

<!-- $HOME/.local/share/agent-skills/handoff/SKILL.md -->
# Handoff

The file is the contract. Resume does not trust it until live state is re-checked.
Resume reports and stops. It does not start work.

## Root

Resolve the handoff root in this order:

1. A path the user names in the request.
2. The handoff root named in the active harness instructions.
3. Ask. Do not invent a root.

Write `<root>/<Project>/<slug>-handoff-<YYYY-MM-DD>.md`. Slug first, then the
date. Do not overwrite an older file.

## Verbs

- `save`: write a new open handoff. Run only when the user asked to save one, or
  invoked the handoff command with no other verb. A passing mention does not
  write a file.
- `resume`: read, verify, report, stop.
- `integrate`: read and verify a handoff, then use its validated context in this
  session. Do not close or modify the handoff.
- `list`: print open handoffs and stop.
- `close`: set `status: closed` and a `closed` date. Do not delete the file.

## Save

1. Name the project and slug. If either is ambiguous, ask.
2. Run `scripts/snapshot.sh` in each repository the session touched. If shell is
   not allowed, say state was not captured and continue. Do not print the
   environment, file contents, or secret files.
3. Scan the draft and the snapshot output before writing. Do not write a
   private-key block, a cloud access key, a service token, or a password
   assignment that carries a value. Report the class of the hit, not the value,
   and stop.
4. Write the file from the template below. Record tracker issues as an id plus a
   title. Do not transition them. Do not create a commit.
5. If an older open handoff has the same project and slug, set `supersedes` to
   that path and mark the older file closed in the same write. A different slug
   stays open.
6. Reply with the path, the summary, and the next steps. Do not paste the whole
   file.
7. If a fact should outlive this task, say so. Do not bury it only in the
   handoff, and do not copy handoff status into a README.

## Resume

1. If no project was named, list open handoffs and stop.
2. Read the newest `status: open` file for that project. Two open slugs: list
   them and ask. A file with no frontmatter is not current. Offer the newest
   name match and ask before using it.
3. Re-run `scripts/snapshot.sh` in the recorded working directory. Diff it
   against the State section.
4. If the handoff names tracker issues, re-read their status. Do not transition
   them.
5. Report the path, the summary, drift or "state matches", the first unfinished
   step, and blockers.
6. Stop. Do not relitigate Decided. Do not start work until the user says to
   continue.

## Integrate

Use Resume steps 1-5 to select and verify the handoff, including live repository
and tracker state. Report the path, summary, drift, first unfinished step, and
blockers. Incorporate verified decisions, constraints, and pointers into the
current session; identify stale or conflicting details instead of treating them
as current facts. Unlike `resume`, do not stop the session after reporting. An
integration request alone does not authorize executing the handoff's Next steps
or broadening the current task. Leave the handoff open.

In Plan mode, read and integrate normally; use the read-only snapshot script.
Save and close may edit only the authorized handoff root, never project files.
If the selected root is not writable under the active agent's permissions,
report the limitation rather than using a shell command to bypass it.

## List and close

List reads frontmatter and prints open files only. Close writes `status: closed`
and `closed: <YYYY-MM-DD>` on the named file. Confirm the path in the reply.

## Template

```yaml
project:
slug:
status: open
created:
pickup:
supersedes:
cwd:
branch:
```

Sections, in order:

- One paragraph that states the point.
- Summary
- Done
- Decided. One line under the heading: do not relitigate.
- State. Branch, dirty files, worktrees. Say when no commit was created.
- Next. Numbered, in order.
- Blockers
- Do not
- Pointers. Related notes and tracker issues as an id plus a title.

Use bullets. A table only when the data is a comparison matrix. No em-dashes.
