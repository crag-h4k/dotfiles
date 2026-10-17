const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function loadPlugin(ts, sourcePath, workflow, notifications = []) {
  const compiled = ts.transpileModule(fs.readFileSync(sourcePath, "utf8"), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX },
    fileName: sourcePath,
    reportDiagnostics: true,
  })
  assert.equal(compiled.diagnostics?.length ?? 0, 0)

  const module = { exports: {} }
  const requirePlugin = (id) => {
    if (id === "@opencode/plugin/tui") return { Plugin: { define: (definition) => definition } }
    if (id === "@opentui/solid/jsx-runtime") return { jsx: () => null, jsxs: () => null }
    if (id === "./workflow.mjs") return workflow
    if (id === "../../plugin/notify-shim.mjs") return { fire: (group) => notifications.push(group) }
    throw new Error(`unexpected import: ${id}`)
  }
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, require: requirePlugin,
  }, { filename: sourcePath })
  return module.exports.default
}

async function verifyAutoAgentName(ts, sourcePath) {
  const compiled = ts.transpileModule(fs.readFileSync(sourcePath, "utf8"), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  })
  const module = { exports: {} }
  vm.runInNewContext(compiled.outputText, {
    module,
    exports: module.exports,
    require: (id) => {
      if (id === "@opencode/plugin") return {
        Plugin: { define: (definition) => definition },
        Agent: { Name: { make: (name) => name } },
      }
      throw new Error(`unexpected import: ${id}`)
    },
  })
  const auto = { name: "auto" }
  await module.exports.default.setup({ agent: {
    transform: async (callback) => callback({ update: (id, change) => {
      assert.equal(id, "auto")
      change(auto)
    } }),
  } })
  assert.equal(auto.name, "Auto")
}

async function verifySessionWorkflowPlugin(ts, sourcePath, workflow) {
  const notifications = []
  const plugin = loadPlugin(ts, sourcePath, workflow, notifications)
  assert.equal(plugin.id, "dotfiles.session-workflow.tui")

  const sessions = new Map([
    ["recent", { id: "recent", agent: "build" }],
    ["unread", { id: "unread", agent: "build" }],
  ])
  let route = { type: "session", sessionID: "recent" }
  let commands
  const handlers = {}
  const replies = []
  const lookups = []
  const context = {
    data: {
      on: (type, handler) => { handlers[type] = handler; return () => {} },
      session: { invalidate: () => {}, root: (id) => id },
    },
    client: {
      session: {
        get: async ({ sessionID }) => { lookups.push(sessionID); return sessions.get(sessionID) },
        switchAgent: async ({ sessionID, agent }) => { sessions.get(sessionID).agent = agent },
      },
      permission: {
        reply: async (reply) => { replies.push(reply) },
        list: async () => [{ id: "request" }],
      },
    },
    keymap: { layer: (factory) => { commands = factory().commands } },
    ui: {
      toast: { show: () => {} },
      router: { current: () => route },
      slot: (claim) => { if (claim.append === "app") claim.render({}); return () => {} },
    },
  }
  const dispose = plugin.setup(context)
  const run = (id) => commands.find((command) => command.id === id).run()

  route = { type: "home" }
  assert.equal(run("dotfiles.mode.cycle"), false)
  assert.equal(lookups.length, 0)
  route = { type: "plugin", name: "test" }
  assert.equal(run("dotfiles.mode.cycle"), false)
  assert.equal(lookups.length, 0)
  route = { type: "session", sessionID: "recent" }

  await run("dotfiles.mode.cycle")
  assert.equal(sessions.get("recent").agent, "plan")
  await run("dotfiles.mode.cycle")
  assert.equal(sessions.get("recent").agent, "auto")
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
  for (let n = 0; n < 20 && !replies.length; n++) await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(replies.map((reply) => ({ ...reply })), [{ sessionID: "recent", requestID: "request", decision: "once" }])
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "form", action: "question" } })
  handlers["permission.asked"]({ data: { sessionID: "unread", id: "other", action: "edit" } })
  sessions.get("recent").agent = "plan"
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "plan", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(replies.length, 1)
  sessions.get("recent").agent = "auto"
  await run("dotfiles.mode.cycle")
  assert.equal(sessions.get("recent").agent, "build")
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "manual", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(replies.length, 1)

  sessions.get("recent").agent = "auto"
  let finishApproval
  let replyStarted = false
  context.client.permission.reply = () => {
    replyStarted = true
    return new Promise((resolve) => { finishApproval = resolve })
  }
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(replyStarted, true)
  assert.deepEqual(notifications, [], "an unresolved Auto approval must not notify")
  // Complete well after the old grace period to reproduce the original race.
  await new Promise((resolve) => setTimeout(resolve, 400))
  assert.deepEqual(notifications, [], "slow successful approval must remain silent")
  finishApproval()
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(notifications, [])

  context.client.permission.reply = async () => { throw Error("approval failed") }
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(notifications, ["opencode_permission"], "failed approval needs manual attention")

  context.client.permission.list = async () => []
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 1, "another client's approval must suppress a stale failure alert")

  context.client.permission.list = async () => [{ id: "request" }]
  sessions.get("unread").agent = "auto"
  handlers["permission.asked"]({ data: { sessionID: "unread", id: "request", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 1, "another session must not flag this pane")

  const delayedFailure = async () => {
    let resolve
    context.client.permission.list = () => new Promise((done) => { resolve = done })
    handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
    await new Promise((done) => setImmediate(done))
    return resolve
  }
  let resolveFailure = await delayedFailure()
  handlers["permission.replied"]({ data: { sessionID: "recent", requestID: "request" } })
  resolveFailure([{ id: "request" }])
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 1, "a matching reply cancels an in-flight stale list response")

  resolveFailure = await delayedFailure()
  handlers["form.created"]({ data: { form: { sessionID: "recent" } } })
  resolveFailure([{ id: "request" }])
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 1, "a newer question must not be overwritten by an older failure check")

  resolveFailure = await delayedFailure()
  handlers["permission.replied"]({ data: { sessionID: "unread", requestID: "request" } })
  handlers["form.created"]({ data: { form: { sessionID: "unread" } } })
  resolveFailure([{ id: "request" }])
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 2, "unrelated replies and forms must not suppress a pending failure")

  let finishPendingCheck
  context.client.permission.list = () => new Promise((resolve) => { finishPendingCheck = resolve })
  handlers["permission.asked"]({ data: { sessionID: "recent", id: "request", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  dispose()
  finishPendingCheck([{ id: "request" }])
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(notifications.length, 2, "plugin disposal cancels delayed failure alerts")
}

module.exports = { verifyAutoAgentName, verifySessionWorkflowPlugin }
