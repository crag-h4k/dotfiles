import assert from "node:assert/strict"
import test from "node:test"
import { rankTabs, reorderTabs } from "../home/dot_config/opencode/plugins/priority-tabs/priority.mjs"

test("pending input is rightmost, then unread, then recently viewed", () => {
  const entries = [
    { sessionID: "recent", viewed: 30 },
    { sessionID: "permission", viewed: 5, pending: true },
    { sessionID: "old", viewed: 10 },
    { sessionID: "question", viewed: 2, pending: true },
    { sessionID: "unread", viewed: 20, unread: true },
  ]
  const expected = ["old", "recent", "unread", "question", "permission"]
  assert.deepEqual(rankTabs(entries).map((entry) => entry.sessionID), expected)
  const moves = []
  assert.deepEqual(reorderTabs(entries, (id, index) => { moves.push([id, index]); return true }), expected)
  assert.deepEqual(reorderTabs(rankTabs(entries), () => { throw new Error("already sorted") }), expected)
  assert.ok(moves.length > 0)
})
