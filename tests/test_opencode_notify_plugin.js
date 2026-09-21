// tests/test_opencode_notify_plugin.js
// Exercise the OpenCode V2 notifier plugin after TypeScript transpilation.

const assert = require("node:assert/strict")
const fs = require("node:fs")
const vm = require("node:vm")

async function waitFor(predicate, description) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) return
    await new Promise((resolve) => setImmediate(resolve))
  }
  throw new Error(`timed out waiting for ${description}`)
}

function loadPlugin(ts, sourcePath, env, spawns) {
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
    process: { env },
    require: fakeRequire,
    setTimeout,
  }
  vm.runInNewContext(compiled.outputText, context, { filename: sourcePath })
  return module.exports.default
}

function eventContext(events, state) {
  return {
    event: {
      async *subscribe({ signal }) {
        state.signal = signal
        for (const type of events) yield { type }
        await new Promise((resolve) => signal.addEventListener("abort", resolve))
      },
    },
  }
}

async function verifyNotifyPlugin(ts, sourcePath) {
  const spawns = []
  const env = {
    HOME: "/test/home",
    TMUX: "/test/tmux/default,1,0",
    TMUX_PANE: "%42",
  }
  const plugin = loadPlugin(ts, sourcePath, env, spawns)
  assert.equal(plugin.id, "notify")

  const state = {}
  const dispose = await plugin.setup(eventContext([
    "session.execution.succeeded",
    "permission.asked",
    "form.created",
    "unrelated.event",
  ], state))

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
    "session.execution.succeeded",
  ], noTmuxState))
  await new Promise((resolve) => setImmediate(resolve))
  assert.equal(spawns.length, 3, "events outside tmux must not spawn the shim")
  noTmuxDispose()
}

module.exports = { verifyNotifyPlugin }
