// tests/test_opencode_attention_rank.mjs
import assert from "node:assert/strict"
import test from "node:test"
import {
  RANK,
  familyState,
  livePins,
  nextUrgent,
  planMoves,
  sinkState,
  targetOrder,
  topOther,
  urgentOrder,
} from "../home/dot_config/opencode/v2-plugins/attention-tabs/rank.mjs"

const tab = (sessionID, rank = 0, since = 0, kind) => ({
  sessionID,
  rank,
  since,
  kind: kind ?? ({ 4: "permission", 3: "question", 2: "completion", 0: "none" })[rank],
})

// Apply a plan with the host's remove-then-insert move semantics.
function apply(order, plan) {
  const result = [...order]
  for (const { id, index } of plan) {
    result.splice(result.indexOf(id), 1)
    result.splice(index, 0, id)
  }
  return result
}

const ids = (entries) => entries.map((entry) => entry.sessionID)

test("the ladder puts permission and error above question above completion above idle", () => {
  assert.deepEqual(RANK, { permission: 4, error: 4, question: 3, completion: 2, none: 0 })
  const one = (extra) => familyState({ members: [{ permissions: 0, questions: 0, updated: 5 }], updated: 5, ...extra })
  assert.deepEqual(one({}), { kind: "none", rank: 0, since: 0 })
  assert.equal(one({ unread: "activity" }).rank, 2)
  assert.equal(one({ unread: "error" }).kind, "error")
  assert.equal(one({ unread: "error" }).rank, 4)
  assert.equal(
    familyState({ members: [{ permissions: 0, questions: 1, updated: 5 }], updated: 5 }).rank,
    3,
  )
  assert.equal(
    familyState({ members: [{ permissions: 1, questions: 0, updated: 5 }], updated: 5 }).kind,
    "permission",
  )
})

test("permission beats a question, an error, and a completion on the same tab", () => {
  const state = familyState({
    members: [{ permissions: 1, questions: 2, updated: 9 }],
    unread: "error",
    updated: 9,
  })
  assert.equal(state.kind, "permission")
  const question = familyState({ members: [{ permissions: 0, questions: 1, updated: 9 }], unread: "activity", updated: 9 })
  assert.equal(question.kind, "question")
})

test("a subagent's pending request lifts the whole tab and dates from that session", () => {
  const state = familyState({
    members: [
      { permissions: 0, questions: 0, updated: 100 },
      { permissions: 1, questions: 0, updated: 70 },
      { permissions: 1, questions: 0, updated: 90 },
    ],
    updated: 100,
  })
  assert.deepEqual(state, { kind: "permission", rank: 4, since: 70 })
})

test("completion and error date from the root session; idle and busy carry no date", () => {
  assert.equal(familyState({ members: [{ permissions: 0, questions: 0, updated: 3 }], unread: "activity", updated: 40 }).since, 40)
  assert.equal(familyState({ members: [{ permissions: 0, questions: 0, updated: 3 }], updated: 40 }).since, 0)
  assert.equal(familyState({ members: [], unread: "error", updated: undefined }).since, 0)
})

test("furthest right is most urgent and rank 0 keeps the order you gave it", () => {
  // Ported from the retired priority-tabs test, minus its viewed tiebreak.
  const entries = [tab("recent"), tab("permission", 4, 5), tab("old"), tab("question", 3, 2), tab("unread", 2, 20)]
  assert.deepEqual(targetOrder(entries, new Set()), ["recent", "old", "unread", "question", "permission"])
})

test("within a rank the longest-waiting tab sits furthest right", () => {
  const entries = [tab("newest", 4, 300), tab("oldest", 4, 100), tab("middle", 4, 200)]
  assert.deepEqual(targetOrder(entries, new Set()), ["newest", "middle", "oldest"])
  const completions = [tab("b", 2, 10), tab("a", 2, 50)]
  assert.deepEqual(targetOrder(completions, new Set()), ["a", "b"])
})

test("equal waits keep the current order so every sorter reaches one target", () => {
  const entries = [tab("x", 3, 7), tab("y", 3, 7), tab("z", 3, 7)]
  assert.deepEqual(targetOrder(entries, new Set()), ["x", "y", "z"])
})

test("visiting a tab never reorders anything: an already ordered bar plans no moves", () => {
  const entries = [tab("a"), tab("b"), tab("c", 2, 5), tab("d", 3, 9), tab("e", 4, 1)]
  assert.deepEqual(planMoves(entries, new Set()), [])
  assert.deepEqual(planMoves([], new Set()), [])
})

test("a newly urgent tab moves once, to the left edge of its class, and nothing else moves", () => {
  const order = ["a", "b", "c", "d", "e"]
  // e has waited longest on a permission; b has just asked for one (the newest); d finished earlier.
  const entries = [tab("a"), tab("b", 4, 90), tab("c"), tab("d", 2, 50), tab("e", 4, 10)]
  const plan = planMoves(entries, new Set())
  assert.deepEqual(plan, [{ id: "b", index: 3 }])
  const result = apply(order, plan)
  assert.deepEqual(result, ["a", "c", "d", "b", "e"])
  // The whole bar is not re-sorted: the untouched tabs keep their relative order.
  assert.deepEqual(result.filter((id) => id !== "b"), ["a", "c", "d", "e"])
})

test("a tab that settled to idle sits beside the idle tabs, not at the far left", () => {
  const entries = [tab("a"), tab("b", 4, 5), tab("c", 2, 7), tab("d")]
  const plan = planMoves(entries, new Set())
  assert.deepEqual(apply(["a", "b", "c", "d"], plan), ["a", "d", "c", "b"])
  // Reversing b, c, d takes two moves; a one-tab change takes one.
  assert.equal(plan.length, 2)
  const stuck = [tab("a"), tab("b"), tab("c", 3, 5), tab("d")]
  assert.deepEqual(apply(["a", "b", "c", "d"], planMoves(stuck, new Set())), ["a", "b", "d", "c"])
})

test("a tab active in any live TUI is never moved and the others sort around it", () => {
  const entries = [tab("a", 4, 5), tab("b"), tab("c", 3, 5), tab("d")]
  const pinned = new Set(["a"])
  const plan = planMoves(entries, pinned)
  assert.ok(plan.every((move) => move.id !== "a"), JSON.stringify(plan))
  const result = apply(["a", "b", "c", "d"], plan)
  assert.deepEqual(result.filter((id) => id !== "a"), ["b", "d", "c"])
  assert.deepEqual(targetOrder(entries, pinned), ["b", "d", "c"])
})

test("pinning every tab plans nothing", () => {
  const entries = [tab("a", 4, 5), tab("b"), tab("c", 3, 5)]
  assert.deepEqual(planMoves(entries, new Set(["a", "b", "c"])), [])
})

test("plans converge, never touch a pinned tab, and use the fewest moves", () => {
  let seed = 7
  const random = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296
  for (let round = 0; round < 300; round += 1) {
    const size = 1 + Math.floor(random() * 9)
    const entries = Array.from({ length: size }, (_, index) =>
      tab(`t${index}`, [0, 0, 2, 3, 4][Math.floor(random() * 5)], Math.floor(random() * 4) * 10),
    )
    const order = ids(entries)
    const pinned = new Set(order.filter(() => random() < 0.25))
    const plan = planMoves(entries, pinned)
    const result = apply(order, plan)
    assert.ok(plan.every((move) => !pinned.has(move.id)), `pinned moved in round ${round}`)
    assert.deepEqual(result.filter((id) => !pinned.has(id)), targetOrder(entries, pinned), `round ${round}`)
    const settled = entries
      .map((entry) => ({ ...entry, order: result.indexOf(entry.sessionID) }))
      .sort((a, b) => a.order - b.order)
    assert.deepEqual(planMoves(settled, pinned), [], `not idempotent in round ${round}`)
    assert.ok(plan.length <= Math.max(0, size - pinned.size - 1), `too many moves in round ${round}`)
  }
})

test("jump order is rank first, then longest-waiting first", () => {
  const entries = [tab("a"), tab("c", 2, 5), tab("q", 3, 9), tab("p1", 4, 50), tab("p2", 4, 20)]
  assert.deepEqual(ids(urgentOrder(entries)), ["p2", "p1", "q", "c"])
})

test("jump repeats through the urgent set and skips the tab you are on", () => {
  const entries = [tab("a"), tab("c", 2, 5), tab("q", 3, 9), tab("p", 4, 20)]
  assert.equal(nextUrgent(entries, "a").sessionID, "p")
  assert.equal(nextUrgent(entries, "p").sessionID, "q")
  assert.equal(nextUrgent(entries, "q").sessionID, "c")
  assert.equal(nextUrgent(entries, "c").sessionID, "p")
  assert.equal(nextUrgent(entries, undefined).sessionID, "p")
  assert.equal(nextUrgent([tab("a"), tab("b")], "a"), undefined)
  assert.equal(nextUrgent([tab("a"), tab("p", 4, 1)], "p"), undefined)
})

test("the banner names the top-ranked tab other than the one in view", () => {
  const entries = [tab("a"), tab("q", 3, 9), tab("p", 4, 20)]
  assert.equal(topOther(entries, "a").sessionID, "p")
  assert.equal(topOther(entries, "p").sessionID, "q")
  assert.equal(topOther([tab("a"), tab("b")], "a"), undefined)
})

test("sink state: the tab in view wins, otherwise the strongest other tab, otherwise clear", () => {
  const permission = [tab("a", 4, 1), tab("b", 3, 2)]
  assert.deepEqual(sinkState(permission, "a"), { key: "own:opencode_permission", args: ["tint", "own", "opencode_permission"] })
  assert.deepEqual(sinkState(permission, "b"), { key: "own:opencode_question", args: ["tint", "own", "opencode_question"] })
  const elsewhere = [tab("a"), tab("b", 3, 2), tab("c", 2, 3)]
  assert.deepEqual(sinkState(elsewhere, "a"), { key: "elsewhere:opencode_question", args: ["tint", "elsewhere", "opencode_question"] })
  assert.deepEqual(sinkState([tab("a", 2, 1)], "a"), { key: "own:opencode", args: ["tint", "own", "opencode"] })
  assert.deepEqual(sinkState([tab("a", 4, 1, "error")], "a").args, ["tint", "own", "opencode_permission"])
  assert.deepEqual(sinkState([tab("a"), tab("b")], "a"), { key: "clear", args: ["tint", "clear"] })
  assert.deepEqual(sinkState([], undefined), { key: "clear", args: ["tint", "clear"] })
  assert.deepEqual(sinkState([tab("p", 4, 1)], undefined), { key: "elsewhere:opencode_permission", args: ["tint", "elsewhere", "opencode_permission"] })
})

test("live pins are every other TUI's active tab until the entry expires", () => {
  const store = {
    tuis: {
      me: { tab: "mine", at: 1000 },
      fresh: { tab: "theirs", at: 990 },
      stale: { tab: "gone", at: 100 },
      home: { tab: null, at: 995 },
      junk: "not an entry",
    },
  }
  assert.deepEqual([...livePins(store, { now: 1000, ttlMs: 100, self: "me" })].sort(), ["theirs"])
  assert.deepEqual([...livePins(store, { now: 1000, ttlMs: 10, self: "me" })], [])
  assert.deepEqual([...livePins(store, { now: 1000, ttlMs: 2000, self: "me" })].sort(), ["gone", "theirs"])
  assert.deepEqual([...livePins(undefined, { now: 1, ttlMs: 5, self: "me" })], [])
  assert.deepEqual([...livePins({ tuis: undefined }, { now: 1, ttlMs: 5, self: "me" })], [])
})
