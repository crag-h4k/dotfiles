import assert from "node:assert/strict"
import { test } from "node:test"
import { notificationGroup } from "../home/dot_config/opencode/plugin/notify-filter.mjs"

const event = (type, sessionID = "root", id = "request") => ({ type, data: { sessionID, id } })
const checks = (agent = "build", parentID) => ({
  getSession: async () => ({ agent, parentID }),
})

test("root completion notifies, child completion does not", async () => {
  assert.equal(await notificationGroup(event("session.execution.succeeded"), checks()), "opencode")
  assert.equal(await notificationGroup(event("session.execution.succeeded", "child"), checks("auto", "root")), undefined)
})

test("Auto approval owns permission notifications without a timing cutoff", async () => {
  assert.equal(await notificationGroup(event("permission.asked"), checks("auto")), undefined)
})

test("a question permission still notifies in Auto", async () => {
  const question = event("permission.asked")
  question.data.action = "question"
  assert.equal(await notificationGroup(question, checks("auto")), "opencode_permission")
})

test("build permissions and question forms notify without waiting", async () => {
  assert.equal(await notificationGroup(event("permission.asked"), checks()), "opencode_permission")
  assert.equal(await notificationGroup({ type: "form.created", data: { form: { sessionID: "root" } } }, checks("auto")), "opencode_question")
})
