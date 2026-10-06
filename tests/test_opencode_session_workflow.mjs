import assert from "node:assert/strict"
import { createRequire } from "node:module"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { nextMode, rankTabs, reorderTabs, shouldAutoApprove } from "../home/dot_config/opencode/plugins/session-workflow/workflow.mjs"

const require = createRequire(import.meta.url)

test("Build, Plan, and Auto cycle without a third agent", () => {
  assert.equal(nextMode("build"), "plan")
  assert.equal(nextMode("plan"), "auto")
  assert.equal(nextMode("auto"), "build")
  assert.equal(nextMode("ricer"), "build")
})

test("Auto replies only for an Auto session's permission requests", () => {
  assert.equal(shouldAutoApprove({ agent: "auto", action: "edit" }), true)
  assert.equal(shouldAutoApprove({ agent: "build", action: "edit" }), false)
  assert.equal(shouldAutoApprove({ agent: "plan", action: "edit" }), false)
  assert.equal(shouldAutoApprove({ agent: "auto", action: "question" }), false)
})

test("native tab order puts pending attention before unread and recent", () => {
  const entries = [
    { sessionID: "old", viewed: 10, unread: false, pending: false, attention: false },
    { sessionID: "unread", viewed: 20, unread: true, pending: false, attention: false },
    { sessionID: "recent", viewed: 30, unread: false, pending: false, attention: false },
    { sessionID: "question", viewed: 2, unread: false, pending: true, attention: false },
    { sessionID: "permission", viewed: 5, unread: false, pending: true, attention: false },
  ]
  assert.deepEqual(rankTabs(entries).map((entry) => entry.sessionID), [
    "permission", "question", "unread", "recent", "old",
  ])
  assert.deepEqual(entries.map((entry) => entry.sessionID)[0], "old")
  const moves = []
  const order = reorderTabs(entries, (id, index) => { moves.push([id, index]); return true })
  assert.deepEqual(order, ["permission", "question", "unread", "recent", "old"])
  assert.deepEqual(moves, [["permission", 0], ["question", 1], ["unread", 2], ["recent", 3]])
  assert.deepEqual(reorderTabs(rankTabs(entries), () => { throw new Error("already sorted") }), order)
})

test("terminal plugin cycles agents and answers asks for only the Auto session", async () => {
  const ts = require("typescript")
  const { verifySessionWorkflowPlugin } = require("./test_opencode_session_workflow_plugin.js")
  await verifySessionWorkflowPlugin(
    ts,
    fileURLToPath(new URL("../home/dot_config/opencode/plugins/session-workflow/tui.tsx", import.meta.url)),
    { nextMode, rankTabs, reorderTabs, shouldAutoApprove },
  )
})

test("server plugin gives the Auto agent a visible name", async () => {
  const ts = require("typescript")
  const { verifyAutoAgentName } = require("./test_opencode_session_workflow_plugin.js")
  await verifyAutoAgentName(
    ts,
    fileURLToPath(new URL("../home/dot_config/opencode/plugins/session-workflow/index.ts", import.meta.url)),
  )
})
