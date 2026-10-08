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
    if (id === "@opencode/plugin/tui") return { Plugin: { define: (definition) => definition } }
    if (id === "@opentui/solid/jsx-runtime") return { jsx: () => null, jsxs: () => null }
    if (id === "./workflow.mjs") return workflow
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
  const plugin = loadPlugin(ts, sourcePath, workflow)
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
      session: { invalidate: () => {} },
    },
    client: {
      session: {
        get: async ({ sessionID }) => { lookups.push(sessionID); return sessions.get(sessionID) },
        switchAgent: async ({ sessionID, agent }) => { sessions.get(sessionID).agent = agent },
      },
      permission: { reply: async (reply) => { replies.push(reply) } },
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

  dispose()
}

module.exports = { verifyAutoAgentName, verifySessionWorkflowPlugin }
