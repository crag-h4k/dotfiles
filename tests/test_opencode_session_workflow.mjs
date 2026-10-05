import assert from "node:assert/strict"
import { createRequire } from "node:module"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { nextMode, rankInbox, shouldAutoApprove } from "../home/dot_config/opencode/plugins/session-workflow/workflow.mjs"

const require = createRequire(import.meta.url)

test("Build, Plan, and Auto cycle without a third agent", () => {
  assert.deepEqual(nextMode("build", false), { agent: "plan", auto: false })
  assert.deepEqual(nextMode("plan", false), { agent: "build", auto: true })
  assert.deepEqual(nextMode("build", true), { agent: "build", auto: false })
  assert.deepEqual(nextMode("ricer", false), { agent: "plan", auto: false })
})

test("Auto replies only for a Build session's permission requests", () => {
  assert.equal(shouldAutoApprove({ enabled: true, agent: "build", action: "edit" }), true)
  assert.equal(shouldAutoApprove({ enabled: false, agent: "build", action: "edit" }), false)
  assert.equal(shouldAutoApprove({ enabled: true, agent: "plan", action: "edit" }), false)
  assert.equal(shouldAutoApprove({ enabled: true, agent: "build", action: "question" }), false)
})

test("pending attention outranks unread activity, then most recently viewed", () => {
  const entries = [
    { sessionID: "old", viewed: 10, unread: false, pending: false, attention: false },
    { sessionID: "unread", viewed: 20, unread: true, pending: false, attention: false },
    { sessionID: "recent", viewed: 30, unread: false, pending: false, attention: false },
    { sessionID: "question", viewed: 2, unread: false, pending: true, attention: false },
    { sessionID: "permission", viewed: 5, unread: false, pending: true, attention: false },
  ]
  assert.deepEqual(rankInbox(entries).map((entry) => entry.sessionID), [
    "permission", "question", "unread", "recent", "old",
  ])
  assert.deepEqual(entries.map((entry) => entry.sessionID)[0], "old")
})

test("terminal plugin cycles agents and answers asks for only the Auto session", async () => {
  const ts = require("typescript")
  const { verifySessionWorkflowPlugin } = require("./test_opencode_session_workflow_plugin.js")
  await verifySessionWorkflowPlugin(
    ts,
    fileURLToPath(new URL("../home/dot_config/opencode/plugins/session-workflow/tui.tsx", import.meta.url)),
    { nextMode, rankInbox, shouldAutoApprove },
  )
})
