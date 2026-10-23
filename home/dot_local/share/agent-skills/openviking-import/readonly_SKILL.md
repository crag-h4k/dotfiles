---
name: openviking-import
description: Import file-based memories and earlier OpenCode 2 sessions into OpenViking. Plans first, writes only approved items, and runs as an OpenCode 2 DAG when dag_start is available so each step shows in the side panel. Use when the user asks to import, sync, backfill, or adopt memory files or past OpenCode sessions into OpenViking, or asks what is missing.
---

# OpenViking import

Two commands cover the two sources. Both default to a read-only plan.

- `openvikingctl import-memory` compares markdown memory files (default
  `$DOTFILES_AGENTS_DIR/memory`) with `viking://~/memories`. It resolves
  symlinks to one canonical copy, skips dangling links and links that leave the
  named sources, and writes files directly into the matching category. No
  extraction model is involved.
- `openvikingctl export-oc2` reads the OpenCode 2 database and writes a private
  snapshot of sessions OpenViking does not hold yet. `openvikingctl
  import-claude --source <snapshot> --name oc2-<date>` then replays it. That
  replay uses the extraction model, so it can send content to a provider and
  can fail on a provider policy rejection.

## Rules

- Start with the plan. Never pass `--apply` without an explicit approval for
  that run, collected with the harness question tool in the main session. A
  child session cannot ask.
- Memory text stays out of the transcript. The plan reports names, actions, and
  line counts. Use `--show-diff NAME` only for a file you are about to
  recommend replacing.
- A changed file is replaced only when the user approves that file name, passed
  as `--update NAME`. Do not generalize one approval to similar files.
- Ask separately before the OpenCode 2 replay, because it uses the extraction
  provider. File memories and session history are independent decisions.
- Use a fresh, empty `--out` directory for every snapshot. A snapshot changed
  after an import started cannot resume.
- Run the commands as written. Do not read the OpenViking client config or key.

## Read a file-memory plan

- `new`: not in OpenViking. Apply writes it, then reads it back to verify.
- `identical`: nothing to do; apply records it so a rerun skips it.
- `present-elsewhere`: the same name exists under another category; left alone.
- `update`: the file changed since the last import and the OpenViking copy did
  not. Needs approval.
- `conflict`: both differ, or there is no import history. Needs approval.
- `openviking-ahead`: the OpenViking copy changed after import; left alone.

Apply rereads each target right before writing. It reports `appeared-since-plan`
for a new file that showed up and `changed-since-plan` for an approved
replacement whose OpenViking copy no longer matches the plan. Both are left
untouched, so nothing written after the plan is overwritten.

For `update` and `conflict`, `newer` says which side has the later timestamp and
`change` counts lines. OpenViking wins unless the file is newer. A newer file is
a proposal, not proof: a bulk edit such as a path rename also bumps a file's
mtime, so show the diff and say what changed before recommending a replacement.
Skipped reasons to relay: `personal-marker` (the index marks the file personal),
`profile-singleton-review` (the profile is one file; review by hand),
`unclassified`, `dangling-link`, `link-outside-sources`, and duplicates.

## Run it as a DAG

When `dag_start` exists (the opencode-sidequest plugin), run the work as two
DAGs so the panel shows each step. Pass a `model` on every step, since an
omitted model falls back to the host default. Host permissions still apply in
child sessions, so the user may see a prompt for each command. Without
`dag_start`, run the same commands in the same order.

Run 1 is read-only:

```json
{
  "name": "memory-import-plan",
  "maxParallel": 2,
  "nodes": [
    {"id": "files-plan", "label": "File memories: plan",
     "prompt": "Run `openvikingctl import-memory` without --apply. Return the summary counts, every file whose action is new, update, or conflict with its newer side and change counts, and the skipped reasons. Do not print memory text. Change nothing."},
    {"id": "oc2-plan", "label": "OpenCode 2 history: plan",
     "prompt": "Run `openvikingctl export-oc2` without --apply. Return the summary counts and the skipped reasons. Change nothing."},
    {"id": "review", "label": "Summarize for approval",
     "depends_on": ["files-plan", "oc2-plan"],
     "prompt": "Combine the two plans into one short proposal: files that would be added, changed files grouped by newer side, how many sessions would be exported, and anything that needs a human decision. Change nothing."}
  ]
}
```

After the user approves, run 2 with only the approved nodes. Replace the
angle-bracket values; omit `--update` unless a file was approved by name.

```json
{
  "name": "memory-import-apply",
  "maxParallel": 2,
  "nodes": [
    {"id": "files-apply", "label": "File memories: write",
     "prompt": "Run `openvikingctl import-memory --apply --update <name> --update <name>`. Report the written, unverified, and appeared-since-plan counts."},
    {"id": "files-verify", "label": "File memories: verify", "depends_on": ["files-apply"],
     "prompt": "Run `openvikingctl import-memory` without --apply. Every approved file should now be identical. Report any that are not."},
    {"id": "oc2-export", "label": "OpenCode 2: export snapshot",
     "prompt": "Run `openvikingctl export-oc2 --apply --out <new empty directory>`. Report the snapshot path and counts."},
    {"id": "oc2-preview", "label": "OpenCode 2: preview replay", "depends_on": ["oc2-export"],
     "prompt": "Run `openvikingctl import-claude --source <snapshot> --name oc2-<date>` without --apply and report the counts."},
    {"id": "oc2-apply", "label": "OpenCode 2: replay", "depends_on": ["oc2-preview"],
     "prompt": "Run `openvikingctl import-claude --source <snapshot> --name oc2-<date> --apply`. Report the completed and terminal-failure counts."}
  ]
}
```

If a replay fails on a provider policy rejection, report it. Add
`--continue-on-extraction-failure` only if the user asks for a bulk run that
should keep going.

## Limits

- Sessions active in the last 24 hours, sub-agent sessions, sessions already in
  OpenViking, and sessions another import covered are skipped by default.
  `--include-children`, `--min-idle-hours`, and `--since` adjust that.
- A rejected or empty extraction can still finish as completed. After a replay,
  check that memories were created rather than trusting the task status.
- Use `openviking-cleanup` for contradictions between memories. This skill only
  moves what is missing or changed.
