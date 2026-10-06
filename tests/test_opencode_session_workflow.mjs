import assert from "node:assert/strict"
import { createRequire } from "node:module"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { nextMode, shouldAutoApprove } from "../home/dot_config/opencode/plugins/session-workflow/workflow.mjs"

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

test("terminal plugin cycles agents and answers asks for only the Auto session", async () => {
  const ts = require("typescript")
  const { verifySessionWorkflowPlugin } = require("./test_opencode_session_workflow_plugin.js")
  await verifySessionWorkflowPlugin(
    ts,
    fileURLToPath(new URL("../home/dot_config/opencode/plugins/session-workflow/tui.tsx", import.meta.url)),
    { nextMode, shouldAutoApprove },
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
