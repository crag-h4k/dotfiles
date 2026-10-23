// ~/.config/opencode/v2-plugins/attention-tabs/rank.mjs
// Pure ranking and move planning for attention-tabs. No host imports, so every
// TUI that reads the same shared state computes the same target order.

// Furthest right is most urgent. Busy and idle are rank 0 and never move a tab.
export const RANK = Object.freeze({ permission: 4, error: 4, question: 3, completion: 2, none: 0 })

export const KIND_LABEL = Object.freeze({
  permission: "Permission needed",
  error: "Error",
  question: "Question waiting",
  completion: "Finished",
})

// One notifier group per class; the notifier owns the colors and sounds.
const SINK_GROUP = Object.freeze({
  permission: "opencode_permission",
  error: "opencode_permission",
  question: "opencode_question",
  completion: "opencode",
})

const finite = (value) => (Number.isFinite(value) ? value : undefined)

function earliest(members) {
  const times = members.map((member) => finite(member.updated)).filter((time) => time !== undefined)
  return times.length > 0 ? Math.min(...times) : 0
}

/**
 * Classify one tab over its whole session family.
 * members: one entry per session in the family, { permissions, questions, updated }.
 * unread: the tab's own "activity" or "error" marker. updated: the root session's.
 * since dates the wait: the earliest session that is actually waiting, so the
 * value is the same in every TUI that reads the same server state.
 */
export function familyState({ members = [], unread, updated } = {}) {
  const permission = members.filter((member) => member.permissions > 0)
  const question = members.filter((member) => member.questions > 0)
  if (permission.length > 0) return { kind: "permission", rank: RANK.permission, since: earliest(permission) }
  if (unread === "error") return { kind: "error", rank: RANK.error, since: finite(updated) ?? 0 }
  if (question.length > 0) return { kind: "question", rank: RANK.question, since: earliest(question) }
  if (unread === "activity") return { kind: "completion", rank: RANK.completion, since: finite(updated) ?? 0 }
  return { kind: "none", rank: RANK.none, since: 0 }
}

function sorted(entries) {
  return entries
    .map((entry, index) => ({ entry, index }))
    .sort((a, b) =>
      a.entry.rank - b.entry.rank ||
      // The longest-waiting tab is furthest right, so the newest wait sorts first.
      (a.entry.rank > 0 ? (Number(b.entry.since) || 0) - (Number(a.entry.since) || 0) : 0) ||
      a.index - b.index,
    )
    .map(({ entry }) => entry)
}

/** Ids of the movable tabs in target order. Rank 0 keeps the order it already has. */
export function targetOrder(entries, pinned = new Set()) {
  return sorted(entries.filter((entry) => !pinned.has(entry.sessionID))).map((entry) => entry.sessionID)
}

// Indices of one longest strictly increasing subsequence.
function longestIncreasing(values) {
  const length = new Array(values.length).fill(1)
  const previous = new Array(values.length).fill(-1)
  let best = -1
  for (let i = 0; i < values.length; i += 1) {
    for (let j = 0; j < i; j += 1) {
      if (values[j] < values[i] && length[j] + 1 > length[i]) {
        length[i] = length[j] + 1
        previous[i] = j
      }
    }
    if (best < 0 || length[i] > length[best]) best = i
  }
  const kept = new Set()
  for (let i = best; i >= 0; i = previous[i]) kept.add(i)
  return kept
}

/**
 * The fewest moves that bring the movable tabs into target order. Pinned tabs
 * are never moved and never ranked. Each index is valid when the moves are
 * applied in order with remove-then-insert semantics, so the plan is correct
 * even though every move shifts the tabs after it.
 */
export function planMoves(entries, pinned = new Set()) {
  const movable = entries.filter((entry) => !pinned.has(entry.sessionID))
  if (movable.length < 2) return []
  const target = targetOrder(entries, pinned)
  const position = new Map(target.map((id, index) => [id, index]))
  const kept = longestIncreasing(movable.map((entry) => position.get(entry.sessionID)))
  const stays = new Set(movable.filter((_, index) => kept.has(index)).map((entry) => entry.sessionID))
  const bar = entries.map((entry) => entry.sessionID)
  const plan = []
  target.forEach((id, k) => {
    if (stays.has(id)) return
    bar.splice(bar.indexOf(id), 1)
    // After its predecessor in target order; the first tab goes before every tab that stays.
    const index = k > 0
      ? bar.indexOf(target[k - 1]) + 1
      : Math.min(...[...stays].map((stay) => bar.indexOf(stay)))
    bar.splice(index, 0, id)
    plan.push({ id, index })
  })
  return plan
}

/** Tabs that need you, most urgent first: highest rank, then longest-waiting. */
export function urgentOrder(entries) {
  return entries
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => entry.rank > 0)
    .sort((a, b) =>
      b.entry.rank - a.entry.rank ||
      (Number(a.entry.since) || 0) - (Number(b.entry.since) || 0) ||
      b.index - a.index,
    )
    .map(({ entry }) => entry)
}

/** The next urgent tab after the one in view, wrapping around; the tab in view is skipped. */
export function nextUrgent(entries, activeID) {
  const urgent = urgentOrder(entries)
  const at = urgent.findIndex((entry) => entry.sessionID === activeID)
  const ordered = at < 0 ? urgent : [...urgent.slice(at + 1), ...urgent.slice(0, at)]
  return ordered[0]
}

/** The top-ranked urgent tab other than the given one. */
export function topOther(entries, currentID) {
  return urgentOrder(entries).find((entry) => entry.sessionID !== currentID)
}

const clear = () => ({ key: "clear", args: ["tint", "clear"] })

/**
 * What the tmux sink should show: the tab in view wins, then the strongest other
 * tab, then nothing. The key names the state so the caller can apply changes only.
 */
export function sinkState(entries, activeID) {
  const own = entries.find((entry) => entry.sessionID === activeID)
  const from = (scope, kind) => ({
    key: `${scope}:${SINK_GROUP[kind]}`,
    args: ["tint", scope, SINK_GROUP[kind]],
  })
  if (own && own.rank > 0) return from("own", own.kind)
  const other = topOther(entries, activeID)
  return other ? from("elsewhere", other.kind) : clear()
}

/**
 * Tabs that are active in some other live TUI. Entries older than ttlMs are
 * ignored, so a crashed TUI stops pinning its tab.
 */
export function livePins(store, { now, ttlMs, self }) {
  const pins = new Set()
  const tuis = store && typeof store === "object" ? store.tuis : undefined
  if (!tuis || typeof tuis !== "object") return pins
  for (const [id, entry] of Object.entries(tuis)) {
    if (id === self || !entry || typeof entry !== "object") continue
    if (typeof entry.tab !== "string" || typeof entry.at !== "number") continue
    if (now - entry.at < ttlMs) pins.add(entry.tab)
  }
  return pins
}
