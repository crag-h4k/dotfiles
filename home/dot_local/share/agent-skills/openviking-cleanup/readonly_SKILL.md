---
name: openviking-cleanup
description: Review OpenViking memories for stale facts, duplicates, copied policies, and unscoped approvals. Use when the user asks to audit, clean up, or consolidate memories; propose decisions in batches and apply only approved changes.
---

# OpenViking memory cleanup

Review what the current user actually remembers, compare questionable claims
with current evidence, and keep a smaller collection without losing useful
history. Start read-only; requesting cleanup does not choose which files to
delete.

## Inventory and review

Use the runtime's registered OpenViking list/glob, read, and search tools.
Inventory `viking://~/memories`; include relevant peer memories under the same
user when they contain overlapping facts. Read canonical files, not generated
`.abstract.md`, `.overview.md`, or `.source.json` sidecars. Do not include other
users, resources, skills, or raw session archives unless requested. Report any
pagination, truncation, or inaccessible scope rather than calling a partial
inventory complete.

Read current instructions and relevant configuration or documentation before
labeling a memory obsolete. Classify candidates by the actual problem:

- Present-tense facts contradicted by verified current state, including floating
  versions and expired deployment-stage descriptions.
- Duplicated facts, transcripts, or intermediate status reports that can become
  one dated outcome or timeline.
- Authorization/policy copies already covered by authoritative instructions,
  or one task's approval generalized into future permission.
- Speculation promoted into a fact, or a preference generalized beyond its
  source request.
- Secret-bearing content, excessive detail, or ambiguous provenance.

Distinguish historical records from current claims. Old events are not wrong
just because services moved. Keep unique preferences and meaningful decisions;
do not delete them merely because a related project guideline exists. If a
source instruction is stale, flag it separately instead of changing it as a
side effect of memory cleanup. Never display secret values in a finding.

## Batched decisions

Present each candidate or coherent group with its exact URI(s), the conflicting
evidence, confidence, and proposed treatment: keep, mark historical/superseded,
edit, merge, or delete. Show the replacement's meaningful content before
requesting approval. Use the harness question tool when available and group
related decisions into a manageable batch.

List every deletion target explicitly, including redundant originals removed
after a merge. Do not infer approval for similar files, another user's memories,
or changes to extraction settings. A vague record saying a trial or deployment
was approved is historical evidence, not permission for a new action.

## Apply and verify

Immediately reread approved targets before changing them. If content or scope
changed since review, stop that item and obtain a new decision. Preserve private
pre-change content or use an appropriate existing backup; never put it in public
source. Prefer exact-string edits for targeted corrections. For a whole-file
condensation, preserve dates, distinct facts, uncertainty, and useful provenance.

When merging, write and verify the keeper before deleting approved redundant
files. Use the registered memory edit/write/delete tools and their supported
index-wait options. Afterward verify changed content, deleted-file absence, and
representative semantic recall. Leave unapproved candidates and original session
archives untouched. Report completed, retained, blocked, and pending items;
do not create another copy of the policy rules just removed.

If a deleted template or policy memory returns, report recurrence and inspect
the extraction configuration before suggesting a fix. Configuration changes
need a separate decision. In OpenViking 0.4.23 the account template editing API
locks `enabled`; the supported User settings API can restrict
`memory_policy.memory_types`. This is an allowlist, so preserve other targets
and types, check explicit session overrides, and disclose how future types are
handled. Verify the installed version before using that contract.

## Built-in consolidation is not a preview

OpenViking 0.4.23 has `ov compile --skill memory` for in-place consolidation.
Its model-generated operations are applied automatically, including deletions;
it does not provide this approval-first workflow. Do not run it as a dry-run or
assume a prompt requesting a report prevents writes. Use native memory primitives
for reviewed changes, or obtain explicit approval for automatic consolidation
of a named scope with an appropriate backup.
