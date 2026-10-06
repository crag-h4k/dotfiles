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
    if (id === "solid-js") return { createEffect: (effect) => effect() }
    if (id === "./workflow.mjs") return workflow
    throw new Error(`unexpected import: ${id}`)
  }
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, require: requirePlugin, setTimeout, clearTimeout, console,
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
  const handlers = {}
  const moves = []
  const replies = []
  const pending = new Set(["pending"])
  const questions = new Set()
  const context = {
    data: {
      on: (type, handler) => { handlers[type] = handler; return () => {} },
      session: {
        get: (id) => sessions.get(id), invalidate: () => {},
        permission: { list: (id) => pending.has(id) ? [{ id: "ask" }] : [], sync: async () => {} },
        form: { list: (id) => questions.has(id) ? [{ id: "form" }] : [], sync: async () => {} },
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
      router: { current: () => route },
      tabs: { list: () => tabs, move: (id, index) => {
        moves.push([id, index])
        const current = tabs.findIndex((tab) => tab.sessionID === id)
        tabs.splice(index, 0, ...tabs.splice(current, 1))
        return true
      } },
      slot: (claim) => { if (claim.append === "app") claim.render({}); return () => {} },
    },
  }
  const dispose = plugin.setup(context)
  const run = (id) => commands.find((command) => command.id === id).run()

  await new Promise((resolve) => setTimeout(resolve, 10))
  assert.deepEqual(tabs.map((tab) => tab.sessionID), ["pending", "unread", "recent"])
  assert.deepEqual(moves.map((move) => Array.from(move)), [["pending", 0], ["unread", 1]])
  assert.equal(tabs.find((tab) => tab.active).sessionID, "recent")

  questions.add("unread")
  handlers["form.created"]({ data: { form: { sessionID: "unread" } } })
  await new Promise((resolve) => setTimeout(resolve, 10))
  assert.deepEqual(tabs.map((tab) => tab.sessionID), ["unread", "pending", "recent"])
  questions.delete("unread")
  handlers["form.replied"]({ data: { sessionID: "unread" } })
  await new Promise((resolve) => setTimeout(resolve, 10))
  assert.deepEqual(tabs.map((tab) => tab.sessionID), ["pending", "unread", "recent"])

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

  dispose()
}

module.exports = { verifyAutoAgentName, verifySessionWorkflowPlugin }
