// tests/test_opencode_notify_plugin.js
// Exercise the OpenCode V2 notifier plugin after TypeScript transpilation.

const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")
const { pathToFileURL } = require("node:url")
const path = require("node:path")

async function waitFor(predicate, description) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return
    await new Promise((resolve) => setImmediate(resolve))
  }
  throw new Error(`timed out waiting for ${description}`)
}

function loadPlugin(ts, sourcePath, env, spawns, filter, argv = ["opencode.exe"]) {
  const source = fs.readFileSync(sourcePath, "utf8")
  const compiled = ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2019,
    },
    fileName: sourcePath,
    reportDiagnostics: true,
  })
  const diagnostics = compiled.diagnostics || []
  assert.equal(diagnostics.length, 0, "notifier plugin must transpile cleanly")

  const module = { exports: {} }
  const fakeRequire = (id) => {
    if (id === "./notify-filter.mjs") return filter
    if (id === "./notify-shim.mjs") {
      const shimPath = path.join(path.dirname(sourcePath), "notify-shim.mjs")
      const shim = ts.transpileModule(fs.readFileSync(shimPath, "utf8"), {
        compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2019 },
      })
      const exports = {}
      vm.runInNewContext(shim.outputText, { exports, process: { env }, require: fakeRequire })
      return exports
    }
    if (id === "@opencode/plugin") {
      return { Plugin: { define: (definition) => definition } }
    }
    if (id === "node:child_process") {
      return {
        spawn(command, args, options) {
          const call = { command, args, options, errorHandler: false, unref: false }
          spawns.push(call)
          return {
            on(event) {
              if (event === "error") call.errorHandler = true
              return this
            },
            unref() {
              call.unref = true
            },
          }
        },
      }
    }
    throw new Error(`unexpected require: ${id}`)
  }
  const context = {
    AbortController,
    Date,
    Promise,
    clearTimeout,
    console,
    exports: module.exports,
    module,
    process: { argv, env },
    require: fakeRequire,
    setTimeout,
  }
  vm.runInNewContext(compiled.outputText, context, { filename: sourcePath })
  return module.exports.default
}

function eventContext(events, state, agent, pending = [{ id: "request" }]) {
  return {
    session: { get: async ({ sessionID }) => ({ agent, parentID: sessionID === "child" ? "root" : undefined }) },
    permission: { list: async () => pending },
    event: {
      async *subscribe({ signal }) {
        state.signal = signal
        for (const event of events) {
          yield event
          await new Promise((resolve) => setImmediate(resolve))
        }
        await new Promise((resolve) => signal.addEventListener("abort", resolve))
      },
    },
  }
}

async function verifyNotifyPlugin(ts, sourcePath) {
  const filter = await import(pathToFileURL(path.join(path.dirname(sourcePath), "notify-filter.mjs")))
  const spawns = []
  const env = {
    HOME: "/test/home",
    TMUX: "/test/tmux/default,1,0",
    TMUX_PANE: "%42",
  }
  const plugin = loadPlugin(ts, sourcePath, env, spawns, filter)
  assert.equal(plugin.id, "notify")

  const state = {}
  const dispose = await plugin.setup(eventContext([
    { type: "session.execution.succeeded", data: { sessionID: "root" } },
    { type: "permission.asked", data: { sessionID: "root", id: "request" } },
    { type: "form.created", data: { form: { sessionID: "root" } } },
    { type: "unrelated.event" },
  ], state, "build"))

  await waitFor(() => spawns.length === 3, "three routed notifier events")
  assert.deepEqual(
    spawns.map((call) => Array.from(call.args)),
    [
      ["/test/home/.config/notify/opencode-events.sh", "fire", "opencode"],
      ["/test/home/.config/notify/opencode-events.sh", "fire", "opencode_permission"],
      ["/test/home/.config/notify/opencode-events.sh", "fire", "opencode_question"],
    ],
  )
  for (const call of spawns) {
    assert.equal(call.command, "bash")
    assert.equal(call.options.detached, true)
    assert.equal(call.options.stdio, "ignore")
    assert.equal(call.errorHandler, true)
    assert.equal(call.unref, true)
  }

  assert.equal(typeof dispose, "function")
  dispose()
  assert.equal(state.signal.aborted, true)

  env.TMUX = ""
  env.TMUX_PANE = ""
  const noTmuxState = {}
  const noTmuxDispose = await plugin.setup(eventContext([
    { type: "session.execution.succeeded", data: { sessionID: "root" } },
  ], noTmuxState, "build"))
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(spawns.length, 3, "events outside tmux must not spawn the shim")
  noTmuxDispose()

  const autoSpawns = []
  const autoState = {}
  const autoPlugin = loadPlugin(ts, sourcePath, {
    HOME: "/test/home", TMUX: "/test/tmux/default,1,0", TMUX_PANE: "%42",
  }, autoSpawns, filter)
  const autoDispose = await autoPlugin.setup(eventContext([
    { type: "permission.asked", data: { sessionID: "root", id: "approved" } },
    { type: "session.execution.succeeded", data: { sessionID: "child" } },
  ], autoState, "auto", []))
  await new Promise((resolve) => setImmediate(resolve))
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(autoSpawns.length, 0, "auto-approved requests and child completions must not notify")
  autoDispose()

  const delayedSpawns = []
  const delayedPlugin = loadPlugin(ts, sourcePath, {
    HOME: "/test/home", TMUX: "/test/tmux/default,1,0", TMUX_PANE: "%42",
  }, delayedSpawns, filter)
  let resolveCompletion
  const completion = new Promise((resolve) => { resolveCompletion = resolve })
  const delayedContext = eventContext([
    { type: "session.execution.succeeded", data: { sessionID: "root" } },
    { type: "form.created", data: { form: { sessionID: "root" } } },
  ], {}, "build")
  delayedContext.session.get = () => completion
  const delayedDispose = await delayedPlugin.setup(delayedContext)
  await waitFor(() => delayedSpawns.length === 1, "question while completion lookup is pending")
  resolveCompletion({ agent: "build" })
  await new Promise((resolve) => setImmediate(resolve))
  assert.deepEqual(delayedSpawns.map((call) => call.args[2]), ["opencode_question"],
    "an older completion must not overwrite a newer question")
  delayedDispose()

  let resolvePermission
  const pendingSession = new Promise((resolve) => { resolvePermission = resolve })
  const answeredState = {}
  const answeredContext = eventContext([
    { type: "permission.asked", data: { sessionID: "root", id: "request" } },
    { type: "permission.replied", data: { sessionID: "root", requestID: "request" } },
  ], answeredState, "build")
  answeredContext.session.get = () => pendingSession
  const answeredDispose = await delayedPlugin.setup(answeredContext)
  await new Promise((resolve) => setImmediate(resolve))
  await new Promise((resolve) => setImmediate(resolve))
  resolvePermission({ agent: "build" })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(delayedSpawns.length, 1, "answered permissions must not raise a late alert")
  answeredDispose()

  let resolveManual
  const manualSession = new Promise((resolve) => { resolveManual = resolve })
  const unrelatedContext = eventContext([
    { type: "permission.asked", data: { sessionID: "root", id: "request" } },
    { type: "permission.replied", data: { sessionID: "child", requestID: "request" } },
  ], {}, "build")
  unrelatedContext.session.get = () => manualSession
  const unrelatedDispose = await delayedPlugin.setup(unrelatedContext)
  await new Promise((resolve) => setImmediate(resolve))
  await new Promise((resolve) => setImmediate(resolve))
  resolveManual({ agent: "build" })
  await waitFor(() => delayedSpawns.length === 2, "manual permission despite an unrelated Auto reply")
  assert.equal(delayedSpawns[1].args[2], "opencode_permission")
  unrelatedDispose()

  let resolveOldCompletion
  let lookups = 0
  const oldCompletion = new Promise((resolve) => { resolveOldCompletion = resolve })
  const continuedContext = eventContext([
    { type: "session.execution.succeeded", data: { sessionID: "root" } },
    { type: "permission.asked", data: { sessionID: "root", id: "request", action: "edit" } },
  ], {}, "auto")
  continuedContext.session.get = () => ++lookups === 1 ? oldCompletion : Promise.resolve({ agent: "auto" })
  const continuedDispose = await delayedPlugin.setup(continuedContext)
  await waitFor(() => lookups === 2, "new Auto work while completion lookup is pending")
  resolveOldCompletion({ agent: "auto" })
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(delayedSpawns.length, 2, "continued Auto work invalidates an older completion")
  continuedDispose()

  const sharedSpawns = []
  const sharedState = {}
  const sharedPlugin = loadPlugin(
    ts,
    sourcePath,
    {
      HOME: "/test/home",
      TMUX: "/test/tmux/default,1,0",
      TMUX_PANE: "%42",
    },
    sharedSpawns,
    filter,
    ["opencode.exe", "serve", "--service"],
  )
  const sharedDispose = await sharedPlugin.setup(eventContext([
    { type: "session.execution.succeeded", data: { sessionID: "root" } },
    { type: "permission.asked", data: { sessionID: "root", id: "request" } },
    { type: "form.created", data: { form: { sessionID: "root" } } },
  ], sharedState, "build"))
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(sharedSpawns.length, 0, "shared service must not target one pane for every session")
  sharedDispose()
}

module.exports = { verifyNotifyPlugin }
