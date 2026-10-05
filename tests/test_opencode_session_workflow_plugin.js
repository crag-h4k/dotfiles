const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

function loadPlugin(ts, sourcePath, workflow) {
  const compiled = ts.transpileModule(fs.readFileSync(sourcePath, "utf8"), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, jsx: ts.JsxEmit.ReactJSX },
    fileName: sourcePath,
    reportDiagnostics: true,
  })
  assert.equal(compiled.diagnostics?.length ?? 0, 0)

  const module = { exports: {} }
  const requirePlugin = (id) => {
    if (id === "@opencode/plugin/tui") return { Plugin: { define: (definition) => definition }, usePlugin: () => ({}) }
    if (id === "@opentui/solid") return { useTerminalDimensions: () => () => ({ height: 24 }) }
    if (id === "@opentui/solid/jsx-runtime") return { jsx: () => null, jsxs: () => null }
    if (id === "solid-js") return {
      createSignal(value) {
        return [() => value, (next) => { value = typeof next === "function" ? next(value) : next; return value }]
      },
      createMemo: (compute) => compute,
      For: () => null,
    }
    if (id === "./workflow.mjs") return workflow
    throw new Error(`unexpected import: ${id}`)
  }
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, require: requirePlugin }, { filename: sourcePath })
  return module.exports.default
}

async function verifySessionWorkflowPlugin(ts, sourcePath, workflow) {
  const plugin = loadPlugin(ts, sourcePath, workflow)
  assert.equal(plugin.id, "dotfiles.session-workflow.tui")

  const sessions = new Map([
    ["recent", { id: "recent", agent: "build", time: { viewed: 30 }, location: { directory: "/project" } }],
    ["unread", { id: "unread", agent: "build", time: { viewed: 20 }, location: { directory: "/project" } }],
    ["pending", { id: "pending", agent: "build", time: { viewed: 10 }, location: { directory: "/project" } }],
  ])
  const tabs = [
    { sessionID: "recent", title: "Recent", active: true },
    { sessionID: "unread", title: "Unread", unread: "activity" },
    { sessionID: "pending", title: "Needs input" },
  ]
  let route = { type: "session", sessionID: "recent" }
  let commands
  let asked
  let focused
  const replies = []
  const context = {
    data: {
      on: (type, handler) => { if (type === "permission.asked") asked = handler; return () => {} },
      session: {
        get: (id) => sessions.get(id), invalidate: () => {},
        permission: { list: (id) => id === "pending" ? [{ id: "ask" }] : [], sync: async () => {} },
        form: { list: () => [], sync: async () => {} },
      },
    },
    client: {
      session: {
        get: async ({ sessionID }) => sessions.get(sessionID),
        switchAgent: async ({ sessionID, agent }) => { sessions.get(sessionID).agent = agent },
      },
      permission: { reply: async (reply) => { replies.push(reply) } },
    },
    keymap: { layer: (factory) => { commands = factory().commands } },
    ui: {
      toast: { show: () => {} },
      router: { current: () => route, navigate: (next) => { route = next }, register: () => () => {} },
      tabs: { list: () => tabs, focus: (id) => { focused = id; return true } },
      slot: (claim) => { if (claim.append === "app") claim.render({}); return () => {} },
    },
  }
  const dispose = plugin.setup(context)
  const run = (id) => commands.find((command) => command.id === id).run()

  await run("dotfiles.mode.cycle")
  assert.equal(sessions.get("recent").agent, "plan")
  await run("dotfiles.mode.cycle")
  assert.equal(sessions.get("recent").agent, "build")
  asked({ data: { sessionID: "recent", id: "request", action: "edit" } })
  for (let n = 0; n < 20 && !replies.length; n++) await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(replies.map((reply) => ({ ...reply })), [{ sessionID: "recent", requestID: "request", decision: "once" }])
  asked({ data: { sessionID: "recent", id: "form", action: "question" } })
  asked({ data: { sessionID: "unread", id: "other", action: "edit" } })
  sessions.get("recent").agent = "plan"
  asked({ data: { sessionID: "recent", id: "plan", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(replies.length, 1)
  sessions.get("recent").agent = "build"
  await run("dotfiles.mode.cycle")
  asked({ data: { sessionID: "recent", id: "manual", action: "edit" } })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(replies.length, 1)

  run("dotfiles.inbox.toggle")
  assert.equal(route.name, "dotfiles.session-inbox")
  run("dotfiles.inbox.open")
  assert.equal(focused, "pending")
  assert.equal(route.sessionID, "pending")
  dispose()
}

module.exports = { verifySessionWorkflowPlugin }
