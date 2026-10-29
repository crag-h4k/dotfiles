// tests/test_opencode_attention_tabs.mjs
import assert from "node:assert/strict"
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test, { after } from "node:test"
import { DEFAULTS, createController, normalizeOptions } from "../home/dot_config/opencode/v2-plugins/attention-tabs/controller.mjs"
import { createSink, resolveCommand } from "../home/dot_config/opencode/v2-plugins/attention-tabs/sink.mjs"

const PLUGIN = new URL("../home/dot_config/opencode/v2-plugins/attention-tabs/", import.meta.url)
const read = (name) => readFileSync(new URL(name, PLUGIN), "utf8")

const scratch = mkdtempSync(join(tmpdir(), "attention-tabs-"))
after(() => rmSync(scratch, { recursive: true, force: true }))

// ---- sink ---------------------------------------------------------------------------------

function spawnSpy() {
  const calls = []
  const spawn = (command, args, options) => {
    const call = { command, args, options, unref: 0, handlers: {} }
    calls.push(call)
    return { on: (name, handler) => { call.handlers[name] = handler }, unref: () => { call.unref += 1 } }
  }
  return { calls, spawn }
}

const TMUX_ENV = { TMUX: "/tmp/tmux-501/default,1,0", TMUX_PANE: "%7" }

test("the sink runs the notifier detached, ignoring its output, and never waits for it", () => {
  const { calls, spawn } = spawnSpy()
  const sink = createSink({ command: "/opt/notify", env: TMUX_ENV, spawn, isExecutable: () => true })
  assert.equal(sink.apply({ key: "own:opencode", args: ["tint", "own", "opencode"] }), true)
  assert.equal(calls.length, 1)
  assert.equal(calls[0].command, "/opt/notify")
  assert.deepEqual(calls[0].args, ["tint", "own", "opencode"])
  assert.equal(calls[0].options.detached, true)
  assert.equal(calls[0].options.stdio, "ignore")
  assert.equal(calls[0].options.env.TMUX_PANE, "%7")
  assert.equal(calls[0].unref, 1)
  assert.equal(typeof calls[0].handlers.error, "function")
  assert.doesNotThrow(() => calls[0].handlers.error(new Error("spawn failed")))
})

test("the sink applies a state change once and never re-applies the same state", () => {
  const { calls, spawn } = spawnSpy()
  const sink = createSink({ command: "/opt/notify", env: TMUX_ENV, spawn, isExecutable: () => true })
  const own = { key: "own:opencode_permission", args: ["tint", "own", "opencode_permission"] }
  assert.equal(sink.apply(own), true)
  assert.equal(sink.apply(own), false)
  assert.equal(sink.apply({ ...own }), false)
  assert.equal(sink.apply({ key: "elsewhere:opencode", args: ["tint", "elsewhere", "opencode"] }), true)
  assert.equal(sink.apply({ key: "clear", args: ["tint", "clear"] }), true)
  assert.equal(sink.apply({ key: "clear", args: ["tint", "clear"] }), false)
  assert.deepEqual(calls.map((call) => call.args.join(" ")), [
    "tint own opencode_permission",
    "tint elsewhere opencode",
    "tint clear",
  ])
})

test("nothing pending at start means nothing to clear, so the sink stays quiet", () => {
  const { calls, spawn } = spawnSpy()
  const sink = createSink({ command: "/opt/notify", env: TMUX_ENV, spawn, isExecutable: () => true })
  assert.equal(sink.apply({ key: "clear", args: ["tint", "clear"] }), false)
  assert.equal(calls.length, 0)
})

test("the sink is a silent no-op without tmux, a pane, or an executable command", () => {
  const state = { key: "own:opencode", args: ["tint", "own", "opencode"] }
  for (const [name, env, isExecutable] of [
    ["TMUX unset", { TMUX_PANE: "%7" }, () => true],
    ["TMUX_PANE unset", { TMUX: "/tmp/x,1,0" }, () => true],
    ["both empty", { TMUX: "", TMUX_PANE: "" }, () => true],
    ["command missing", TMUX_ENV, () => false],
  ]) {
    const { calls, spawn } = spawnSpy()
    const sink = createSink({ command: "/opt/notify", env, spawn, isExecutable })
    assert.equal(sink.available(), false, name)
    assert.doesNotThrow(() => sink.apply(state), name)
    assert.equal(sink.apply(state), false, name)
    assert.equal(calls.length, 0, name)
  }
  const { calls, spawn } = spawnSpy()
  const noCommand = createSink({ command: "", env: TMUX_ENV, spawn, isExecutable: () => true })
  assert.equal(noCommand.apply(state), false)
  assert.equal(calls.length, 0)
})

test("a state skipped while the sink was unavailable is applied once it becomes available", () => {
  const { calls, spawn } = spawnSpy()
  let present = false
  const sink = createSink({ command: "/opt/notify", env: TMUX_ENV, spawn, isExecutable: () => present })
  const state = { key: "elsewhere:opencode_question", args: ["tint", "elsewhere", "opencode_question"] }
  assert.equal(sink.apply(state), false)
  present = true
  assert.equal(sink.apply(state), true)
  assert.equal(calls.length, 1)
})

test("a spawn that throws is contained and retried on the next change", () => {
  let attempts = 0
  const spawn = () => { attempts += 1; throw new Error("EAGAIN") }
  const sink = createSink({ command: "/opt/notify", env: TMUX_ENV, spawn, isExecutable: () => true })
  const state = { key: "own:opencode", args: ["tint", "own", "opencode"] }
  assert.equal(sink.apply(state), false)
  assert.equal(sink.apply(state), false)
  assert.equal(attempts, 2)
})

test("a leading tilde expands to the home directory and nothing else expands", () => {
  assert.equal(resolveCommand("~/.config/notify/opencode-events.sh", "/home/u"), "/home/u/.config/notify/opencode-events.sh")
  assert.equal(resolveCommand("/abs/notify", "/home/u"), "/abs/notify")
  assert.equal(resolveCommand("a~b", "/home/u"), "a~b")
  assert.equal(resolveCommand("", "/home/u"), undefined)
  assert.equal(resolveCommand(undefined, "/home/u"), undefined)
})

test("a real stub command receives the exact argv through a real detached spawn", async () => {
  const log = join(scratch, "argv.log")
  const stub = join(scratch, "stub.sh")
  writeFileSync(stub, `#!/bin/sh\nprintf '%s|%s\\n' "$TMUX_PANE" "$*" >> "${log}"\n`)
  chmodSync(stub, 0o755)
  const sink = createSink({ command: stub, env: { ...process.env, ...TMUX_ENV } })
  assert.equal(sink.available(), true)
  assert.equal(sink.apply({ key: "elsewhere:opencode_question", args: ["tint", "elsewhere", "opencode_question"] }), true)
  assert.equal(sink.apply({ key: "clear", args: ["tint", "clear"] }), true)
  // Detached children are not awaited by the sink, so poll for their output.
  for (let i = 0; i < 400 && !(existsSync(log) && readFileSync(log, "utf8").split("\n").length > 2); i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 25))
  }
  assert.deepEqual(readFileSync(log, "utf8").trim().split("\n").sort(), ["%7|tint clear", "%7|tint elsewhere opencode_question"])
})

test("a missing real command is not available and does not throw", () => {
  const sink = createSink({ command: join(scratch, "absent.sh"), env: { ...process.env, ...TMUX_ENV } })
  assert.equal(sink.available(), false)
  assert.equal(sink.apply({ key: "own:opencode", args: ["tint", "own", "opencode"] }), false)
})

// ---- options ------------------------------------------------------------------------------

test("sorting ships off and the other defaults match the design", () => {
  assert.deepEqual(DEFAULTS, {
    sort: false,
    jumpKey: "<leader>z",
    toast: true,
    banner: true,
    tmuxSink: true,
    notifierCommand: "~/.config/notify/opencode-events.sh",
    debounceMs: 300,
    activeTtlMs: 15000,
    debugLog: undefined,
  })
  assert.deepEqual(normalizeOptions(undefined), DEFAULTS)
  assert.deepEqual(normalizeOptions({}), DEFAULTS)
})

test("options keep valid values and fall back to defaults for invalid ones", () => {
  const options = normalizeOptions({
    sort: true,
    jumpKey: "<leader>g",
    toast: false,
    banner: false,
    tmuxSink: false,
    notifierCommand: "/x/notify",
    debounceMs: 50,
    activeTtlMs: 4000,
    debugLog: "/x/log",
  })
  assert.equal(options.sort, true)
  assert.equal(options.jumpKey, "<leader>g")
  assert.equal(options.toast, false)
  assert.equal(options.banner, false)
  assert.equal(options.tmuxSink, false)
  assert.equal(options.notifierCommand, "/x/notify")
  assert.equal(options.debounceMs, 50)
  assert.equal(options.activeTtlMs, 4000)
  const bad = normalizeOptions({ sort: "yes", debounceMs: -5, activeTtlMs: "soon", jumpKey: 4, toast: "no", notifierCommand: 9 })
  assert.deepEqual(bad, DEFAULTS)
  assert.equal(normalizeOptions({ jumpKey: false }).jumpKey, false)
  assert.equal(normalizeOptions({ jumpKey: "none" }).jumpKey, false)
  assert.equal(normalizeOptions({ jumpKey: "" }).jumpKey, false)
  assert.equal(normalizeOptions({ activeTtlMs: 5 }).activeTtlMs, 1000)
})

// ---- plugin harness -----------------------------------------------------------------------

function fakeClock() {
  let time = 1_000_000
  let seq = 0
  const timers = new Map()
  const add = (fn, ms, every) => {
    seq += 1
    timers.set(seq, { at: time + ms, fn, every })
    return seq
  }
  return {
    now: () => time,
    timers: {
      setTimeout: (fn, ms) => add(fn, ms),
      clearTimeout: (id) => timers.delete(id),
      setInterval: (fn, ms) => add(fn, ms, ms),
      clearInterval: (id) => timers.delete(id),
    },
    advance(ms) {
      const end = time + ms
      for (;;) {
        const due = [...timers.entries()].filter(([, timer]) => timer.at <= end).sort((a, b) => a[1].at - b[1].at)[0]
        if (!due) break
        const [id, timer] = due
        time = timer.at
        if (timer.every) timer.at += timer.every
        else timers.delete(id)
        timer.fn()
      }
      time = end
    },
    size: () => timers.size,
  }
}

function harness({ options = {}, tabs = ["a", "b", "c", "d"], active = "a", route, instanceId = "me", realSink } = {}) {
  const clock = fakeClock()
  const calls = { moves: [], focus: [], toasts: [], sync: [], sink: [] }
  const listeners = new Map()
  const state = {
    tabs: tabs.map((sessionID) => ({
      sessionID,
      title: `title-${sessionID}`,
      active: sessionID === active,
      busy: false,
      attention: false,
      unread: undefined,
    })),
    sessions: Object.fromEntries(tabs.map((id) => [id, { id, time: { updated: 100 }, location: { directory: "/w" } }])),
    permissions: {},
    forms: {},
    route: route ?? { type: "session", sessionID: active },
    pending: [],
    store: { tuis: {} },
  }
  const rootOf = (id) => {
    let current = id
    while (state.sessions[current]?.parentID) current = state.sessions[current].parentID
    return current
  }
  const familyOf = (id) => {
    const root = rootOf(id)
    return Object.keys(state.sessions).filter((candidate) => rootOf(candidate) === root)
  }
  const listOf = (map, id) => (map[id] ? Array.from({ length: map[id] }, (_, index) => ({ id: `${id}-${index}` })) : [])
  const context = {
    options,
    data: {
      on: (type, handler) => {
        if (!listeners.has(type)) listeners.set(type, new Set())
        listeners.get(type).add(handler)
        return () => listeners.get(type).delete(handler)
      },
      session: {
        get: (id) => state.sessions[id],
        root: rootOf,
        family: familyOf,
        permission: {
          list: (id) => listOf(state.permissions, id),
          sync: async (id) => { calls.sync.push(["permission", id]) },
        },
        form: {
          list: (id) => listOf(state.forms, id),
          sync: async (id) => { calls.sync.push(["form", id]) },
        },
      },
    },
    ui: {
      tabs: {
        enabled: () => true,
        list: () => state.tabs.map((tab) => ({ ...tab })),
        move: (id, index) => {
          const from = state.tabs.findIndex((tab) => tab.sessionID === id)
          if (from < 0) return false
          const [tab] = state.tabs.splice(from, 1)
          state.tabs.splice(index, 0, tab)
          calls.moves.push({ id, index })
          return true
        },
        focus: (id) => {
          state.tabs.forEach((tab) => { tab.active = tab.sessionID === id })
          state.route = { type: "session", sessionID: id }
          calls.focus.push(id)
          return true
        },
      },
      toast: { show: (value) => { calls.toasts.push(value) } },
      router: { current: () => state.route },
    },
    keymap: {
      pending: () => state.pending,
      shortcuts: (id) => (id === "attention.jump" ? ["ctrl+x d"] : []),
    },
    storage: {
      store: (_key, { initial }) => {
        Object.assign(state.store, JSON.parse(JSON.stringify(initial)), state.store)
        return [state.store, async (mutation) => { mutation(state.store) }]
      },
    },
  }
  // The default sink is the real one with a recording spawn, so dedupe is the real dedupe.
  const recorder = {
    command: "/opt/notify",
    env: TMUX_ENV,
    isExecutable: () => true,
    spawn: (_command, args) => {
      calls.sink.push(args.join(":"))
      return { on() {}, unref() {} }
    },
  }
  const controller = createController(context, options, {
    now: clock.now,
    timers: clock.timers,
    instanceId,
    sinkDeps: realSink ?? recorder,
  })
  controller.start()
  const emit = (type, data) => [...(listeners.get(type) ?? [])].forEach((handler) => handler({ type, data }))
  return {
    clock,
    calls,
    state,
    context,
    controller,
    emit,
    listeners,
    order: () => state.tabs.map((tab) => tab.sessionID),
    set(id, patch) { Object.assign(state.tabs.find((tab) => tab.sessionID === id), patch) },
    command: (id) => controller.commands().find((command) => command.id === id),
    change() { controller.changed() },
    otherTui(tab, at = clock.now()) { state.store.tuis.other = { tab, at } },
  }
}

const SORT = { sort: true }

test("sorting is off by default: an urgent tab does not move", () => {
  const h = harness()
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(5000)
  assert.deepEqual(h.calls.moves, [])
  assert.deepEqual(h.order(), ["a", "b", "c", "d"])
})

test("with sorting on, an urgent tab moves to the right after the debounce, not before", () => {
  const h = harness({ options: SORT })
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(299)
  assert.deepEqual(h.calls.moves, [])
  h.clock.advance(1)
  assert.deepEqual(h.calls.moves, [{ id: "b", index: 3 }])
  assert.deepEqual(h.order(), ["a", "c", "d", "b"])
})

test("a burst of changes sorts once, a debounce after the last", () => {
  const h = harness({ options: SORT })
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(200)
  h.state.forms.c = 1
  h.change()
  h.clock.advance(200)
  assert.deepEqual(h.calls.moves, [])
  h.clock.advance(100)
  assert.deepEqual(h.order(), ["a", "d", "c", "b"])
  const before = h.calls.moves.length
  h.clock.advance(5000)
  assert.equal(h.calls.moves.length, before)
})

test("the debounce option sets the wait", () => {
  const h = harness({ options: { sort: true, debounceMs: 50 } })
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(49)
  assert.deepEqual(h.calls.moves, [])
  h.clock.advance(1)
  assert.equal(h.calls.moves.length, 1)
})

test("the tab in view is never moved and the rest sort around it", () => {
  const h = harness({ options: SORT, active: "b" })
  h.state.permissions.b = 1
  h.state.forms.c = 1
  h.change()
  h.clock.advance(300)
  assert.ok(h.calls.moves.every((move) => move.id !== "b"))
  assert.deepEqual(h.order().filter((id) => id !== "b"), ["a", "d", "c"])
})

test("a tab active in another live TUI is skipped until its entry expires", () => {
  const h = harness({ options: { sort: true, activeTtlMs: 15000 } })
  h.otherTui("b")
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(300)
  assert.deepEqual(h.calls.moves, [], "pinned by the other TUI")
  // The other TUI never heartbeats again; the entry ages out and the next tick sorts.
  h.clock.advance(16000)
  assert.deepEqual(h.calls.moves, [{ id: "b", index: 3 }])
})

test("a live heartbeat from the other TUI keeps its tab pinned", () => {
  const h = harness({ options: { sort: true, activeTtlMs: 15000 } })
  h.state.permissions.b = 1
  h.change()
  h.state.store.tuis.other = { tab: "b", at: h.clock.now() }
  for (let i = 0; i < 6; i += 1) {
    h.clock.advance(5000)
    h.state.store.tuis.other = { tab: "b", at: h.clock.now() }
  }
  assert.deepEqual(h.calls.moves, [])
})

test("each TUI publishes its active tab and heartbeat, and removes its entry on cleanup", () => {
  const h = harness({ options: { sort: true, activeTtlMs: 15000 } })
  h.change()
  assert.deepEqual(h.state.store.tuis.me, { tab: "a", at: h.clock.now() })
  const first = h.state.store.tuis.me.at
  h.clock.advance(6000)
  assert.ok(h.state.store.tuis.me.at > first, "heartbeat refreshed the entry")
  h.controller.focus("c")
  h.change()
  assert.equal(h.state.store.tuis.me.tab, "c")
  h.controller.dispose()
  assert.equal(h.state.store.tuis.me, undefined)
})

test("long-dead entries from other TUIs are pruned by the next write", () => {
  const h = harness({ options: { sort: true, activeTtlMs: 1000 } })
  h.state.store.tuis.ghost = { tab: "c", at: h.clock.now() - 100000 }
  h.state.store.tuis.fresh = { tab: "d", at: h.clock.now() }
  h.change()
  h.clock.advance(1000)
  assert.equal(h.state.store.tuis.ghost, undefined)
})

test("sorting pauses while a leader chord is pending and resumes after it", () => {
  const h = harness({ options: SORT })
  h.state.pending = [{ key: "ctrl+x" }]
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(1500)
  assert.deepEqual(h.calls.moves, [])
  h.state.pending = []
  h.clock.advance(300)
  assert.equal(h.calls.moves.length, 1)
})

test("attention.sort.pause toggles sorting for manual drags", () => {
  const h = harness({ options: SORT })
  const pause = h.command("attention.sort.pause")
  assert.ok(pause)
  pause.run()
  assert.equal(h.controller.isPaused(), true)
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(2000)
  assert.deepEqual(h.calls.moves, [])
  pause.run()
  assert.equal(h.controller.isPaused(), false)
  h.clock.advance(300)
  assert.equal(h.calls.moves.length, 1)
  assert.equal(h.calls.toasts.length, 2)
})

test("pausing says so when sorting is off in the options", () => {
  const h = harness()
  h.command("attention.sort.pause").run()
  assert.equal(h.controller.isPaused(), false)
  assert.match(h.calls.toasts.at(-1).message, /off/i)
})

test("an error and a completion rank by the ladder through the tab's unread marker", () => {
  const h = harness({ options: SORT })
  h.set("b", { unread: "activity" })
  h.set("c", { unread: "error" })
  h.state.sessions.b.time.updated = 50
  h.state.sessions.c.time.updated = 60
  h.change()
  h.clock.advance(300)
  assert.deepEqual(h.order(), ["a", "d", "b", "c"])
})

test("a subagent's permission lifts its parent's tab", () => {
  const h = harness({ options: SORT })
  h.state.sessions.child = { id: "child", parentID: "b", time: { updated: 70 }, location: { directory: "/w" } }
  h.state.permissions.child = 1
  h.change()
  h.clock.advance(300)
  assert.deepEqual(h.order(), ["a", "c", "d", "b"])
})

// toast

test("another tab's permission or question raises a clickable toast for that tab's root", () => {
  const h = harness()
  h.emit("permission.asked", { id: "p1", sessionID: "c", action: "bash", resources: ["ls"] })
  assert.equal(h.calls.toasts.length, 1)
  assert.equal(h.calls.toasts[0].sessionID, "c")
  assert.equal(h.calls.toasts[0].variant, "warning")
  assert.match(h.calls.toasts[0].message, /Permission needed/)
  assert.match(h.calls.toasts[0].message, /bash/)
  h.emit("form.created", { form: { id: "f1", sessionID: "d", title: "Which database?", fields: [] } })
  assert.equal(h.calls.toasts.length, 2)
  assert.equal(h.calls.toasts[1].sessionID, "d")
  assert.equal(h.calls.toasts[1].variant, "info")
  assert.match(h.calls.toasts[1].message, /Which database\?/)
})

test("a request in the tab you are on, or in its subagent, raises no toast", () => {
  const h = harness()
  h.state.sessions.child = { id: "child", parentID: "a", time: { updated: 1 }, location: {} }
  h.emit("permission.asked", { id: "p1", sessionID: "a", action: "edit", resources: [] })
  h.emit("permission.asked", { id: "p2", sessionID: "child", action: "edit", resources: [] })
  h.emit("form.created", { form: { id: "f1", sessionID: "child", title: "x", fields: [] } })
  assert.deepEqual(h.calls.toasts, [])
})

test("a subagent of another tab toasts that tab's root", () => {
  const h = harness()
  h.state.sessions.child = { id: "child", parentID: "c", time: { updated: 1 }, location: {} }
  h.emit("permission.asked", { id: "p1", sessionID: "child", action: "edit", resources: [] })
  assert.equal(h.calls.toasts[0].sessionID, "c")
})

test("from the home screen every request toasts", () => {
  const h = harness({ route: { type: "home" } })
  h.emit("permission.asked", { id: "p1", sessionID: "a", action: "edit", resources: [] })
  assert.equal(h.calls.toasts.length, 1)
})

test("the toast option turns toasts off", () => {
  const h = harness({ options: { toast: false } })
  h.emit("permission.asked", { id: "p1", sessionID: "c", action: "edit", resources: [] })
  assert.deepEqual(h.calls.toasts, [])
})

test("a request refreshes that session's lists so its tab can rank", () => {
  const h = harness()
  h.emit("permission.asked", { id: "p1", sessionID: "c", action: "edit", resources: [] })
  h.emit("form.created", { form: { id: "f1", sessionID: "d", title: "x", fields: [] } })
  assert.ok(h.calls.sync.some(([kind, id]) => kind === "permission" && id === "c"))
  assert.ok(h.calls.sync.some(([kind, id]) => kind === "form" && id === "d"))
})

// banner

test("the banner appears only while another tab needs you, and names the class and tab", () => {
  const h = harness()
  assert.equal(h.controller.bannerTarget("a"), undefined)
  h.state.permissions.c = 1
  const banner = h.controller.bannerTarget("a")
  assert.equal(banner.sessionID, "c")
  assert.equal(banner.kind, "permission")
  assert.match(banner.label, /^Permission needed: title-c/)
  assert.match(banner.label, /ctrl\+x d/)
  assert.equal(h.controller.bannerTarget("c"), undefined, "the tab itself is not 'another tab'")
})

test("the banner skips unread completion but still shows another pending request", () => {
  const h = harness()
  h.set("b", { unread: "activity" })
  assert.equal(h.controller.bannerTarget("a"), undefined)

  h.state.forms.c = 1
  const banner = h.controller.bannerTarget("a")
  assert.equal(banner.sessionID, "c")
  assert.equal(banner.kind, "question")
})

test("the banner offers the top-ranked tab, and only the banner option shows it", () => {
  const h = harness()
  h.state.forms.b = 1
  h.state.permissions.d = 1
  assert.equal(h.controller.bannerTarget("a").sessionID, "d")
  assert.equal(h.controller.bannerTarget("d").sessionID, "b")
  const off = harness({ options: { banner: false } })
  off.state.permissions.c = 1
  assert.equal(off.controller.bannerTarget("a"), undefined)
})

test("clicking the banner focuses the tab it names", () => {
  const h = harness()
  h.state.permissions.c = 1
  h.controller.focus(h.controller.bannerTarget("a").sessionID)
  assert.deepEqual(h.calls.focus, ["c"])
})

// jump

test("attention.jump is a palette command with a slash name and the jumpKey binding", () => {
  const h = harness()
  const jump = h.command("attention.jump")
  assert.equal(jump.palette, true)
  assert.equal(jump.bind, "<leader>z")
  assert.ok(jump.slash.name)
  assert.ok(jump.title)
  assert.equal(h.command("attention.sort.pause").bind, false)
  const custom = harness({ options: { jumpKey: "<leader>g" } })
  assert.equal(custom.command("attention.jump").bind, "<leader>g")
  const unbound = harness({ options: { jumpKey: false } })
  assert.equal(unbound.command("attention.jump").bind, false)
})

test("attention.jump focuses the top-ranked tab and repeats through the urgent set in rank order", () => {
  const h = harness({ tabs: ["a", "b", "c", "d", "e"] })
  h.state.sessions.b.time.updated = 10
  h.state.sessions.c.time.updated = 20
  h.state.sessions.d.time.updated = 30
  h.set("b", { unread: "activity" })
  h.state.forms.c = 1
  h.state.permissions.d = 1
  const jump = h.command("attention.jump")
  jump.run()
  jump.run()
  jump.run()
  jump.run()
  assert.deepEqual(h.calls.focus, ["d", "c", "b", "d"])
})

test("attention.jump does nothing when no other tab needs you", () => {
  const h = harness()
  h.command("attention.jump").run()
  assert.deepEqual(h.calls.focus, [])
  h.state.permissions.a = 1
  h.command("attention.jump").run()
  assert.deepEqual(h.calls.focus, [])
})

// tmux sink wiring

test("the sink follows the derived state and applies only changes", () => {
  const h = harness()
  h.change()
  h.change()
  assert.deepEqual(h.calls.sink, [], "nothing pending: nothing to clear at start")
  h.state.forms.c = 1
  h.change()
  h.change()
  h.change()
  assert.deepEqual(h.calls.sink, ["tint:elsewhere:opencode_question"])
  h.set("c", { active: true })
  h.set("a", { active: false })
  h.change()
  assert.deepEqual(h.calls.sink, ["tint:elsewhere:opencode_question", "tint:own:opencode_question"])
  h.state.forms.c = 0
  h.change()
  assert.deepEqual(h.calls.sink.at(-1), "tint:clear")
})

test("the tab in view wins the tint over another tab's class", () => {
  const h = harness()
  h.state.permissions.c = 1
  h.state.forms.a = 1
  h.change()
  assert.deepEqual(h.calls.sink, ["tint:own:opencode_question"])
})

test("a recompute from the heartbeat never re-applies an unchanged state", () => {
  const h = harness()
  h.state.permissions.c = 1
  h.change()
  h.clock.advance(60000)
  assert.deepEqual(h.calls.sink, ["tint:elsewhere:opencode_permission"])
})

test("with tmux and a command, the controller runs the notifier through the sink", () => {
  const { calls, spawn } = spawnSpy()
  const h = harness({ realSink: { command: "/opt/notify", spawn, env: TMUX_ENV, isExecutable: () => true } })
  assert.equal(h.controller.sinkAvailable(), true)
  h.state.permissions.c = 1
  h.change()
  h.change()
  assert.equal(calls.length, 1)
  assert.deepEqual(calls[0].args, ["tint", "elsewhere", "opencode_permission"])
  assert.equal(calls[0].options.detached, true)
})

test("tmuxSink false builds no sink and never spawns", () => {
  const { calls, spawn } = spawnSpy()
  const h = harness({
    options: { tmuxSink: false },
    realSink: { command: "/opt/notify", spawn, env: TMUX_ENV, isExecutable: () => true },
  })
  assert.equal(h.controller.sinkAvailable(), false)
  h.state.permissions.c = 1
  h.change()
  assert.equal(calls.length, 0)
})

test("without tmux the plugin still sorts, toasts, and jumps", () => {
  const { calls, spawn } = spawnSpy()
  const h = harness({
    options: SORT,
    realSink: { command: "/opt/notify", spawn, env: {}, isExecutable: () => true },
  })
  assert.equal(h.controller.sinkAvailable(), false)
  h.state.permissions.b = 1
  h.change()
  h.clock.advance(300)
  assert.equal(calls.length, 0)
  assert.deepEqual(h.order(), ["a", "c", "d", "b"])
  h.emit("permission.asked", { id: "p", sessionID: "c", action: "x", resources: [] })
  assert.equal(h.calls.toasts.length, 1)
  h.command("attention.jump").run()
  assert.deepEqual(h.calls.focus, ["b"])
})

// lifecycle

test("cleanup removes every listener, timer, and stored entry, and setup can run again", () => {
  const h = harness({ options: SORT })
  h.change()
  h.state.permissions.b = 1
  h.change()
  assert.ok([...h.listeners.values()].some((set) => set.size > 0))
  h.controller.dispose()
  for (const [type, set] of h.listeners) assert.equal(set.size, 0, `listener left on ${type}`)
  assert.equal(h.clock.size(), 0, "a timer survived cleanup")
  assert.equal(h.state.store.tuis.me, undefined)
  h.emit("permission.asked", { id: "p", sessionID: "c", action: "x", resources: [] })
  assert.deepEqual(h.calls.toasts, [])
  h.clock.advance(60000)
  assert.deepEqual(h.calls.moves, [])
})

test("setup, cleanup, setup leaves one live set of listeners and one toast per request", () => {
  const h = harness()
  const counts = () => [...h.listeners.values()].reduce((sum, set) => sum + set.size, 0)
  const live = counts()
  assert.ok(live > 0)
  h.controller.dispose()
  assert.equal(counts(), 0)
  const again = createController(h.context, {}, { now: h.clock.now, timers: h.clock.timers, instanceId: "second", sink: null })
  again.start()
  assert.equal(counts(), live)
  h.emit("permission.asked", { id: "p", sessionID: "c", action: "x", resources: [] })
  assert.equal(h.calls.toasts.length, 1)
  again.dispose()
  assert.equal(counts(), 0)
})

test("a second live controller toasts too, which is why cleanup must remove the first", () => {
  const h = harness()
  const other = createController(h.context, {}, { now: h.clock.now, timers: h.clock.timers, instanceId: "again", sink: null })
  other.start()
  h.emit("permission.asked", { id: "p", sessionID: "c", action: "x", resources: [] })
  assert.equal(h.calls.toasts.length, 2)
  other.dispose()
  h.emit("permission.asked", { id: "p2", sessionID: "c", action: "x", resources: [] })
  assert.equal(h.calls.toasts.length, 3)
})

test("the signature ignores tab order and busy flapping so the plugin's own moves do not retrigger it", () => {
  const h = harness({ options: SORT })
  const before = h.controller.signature()
  h.set("b", { busy: true })
  assert.equal(h.controller.signature(), before)
  h.state.tabs.reverse()
  assert.equal(h.controller.signature(), before)
  h.state.permissions.b = 1
  assert.notEqual(h.controller.signature(), before)
  const withPermission = h.controller.signature()
  h.set("a", { active: false })
  h.set("c", { active: true })
  assert.notEqual(h.controller.signature(), withPermission)
})

test("a tab seen for the first time has its request lists fetched, including its subagents", () => {
  const h = harness()
  h.state.sessions.child = { id: "child", parentID: "b", time: { updated: 1 }, location: { directory: "/w" } }
  h.change()
  assert.ok(h.calls.sync.some(([kind, id]) => kind === "permission" && id === "child"))
  assert.ok(h.calls.sync.some(([kind, id]) => kind === "form" && id === "b"))
  const count = h.calls.sync.length
  h.change()
  assert.equal(h.calls.sync.length, count, "each tab is synced once")
})

// source guards

test("the entry registers one app slot for effects, one banner slot, and one command layer", () => {
  const source = read("tui.tsx")
  assert.match(source, /id: "dotfiles\.attention-tabs"/)
  assert.match(source, /append: "app"/)
  assert.match(source, /append: "session\.composer\.top"/)
  assert.match(source, /keymap\.layer\(/)
  assert.match(source, /onMouseUp/)
  assert.match(source, /ctl\.dispose\(\)/)
  assert.doesNotMatch(source, /\u2014/)
})

test("nothing awaits a child process and no helper process is run synchronously", () => {
  for (const name of ["sink.mjs", "controller.mjs", "rank.mjs", "tui.tsx"]) {
    const source = read(name)
    assert.doesNotMatch(source, /execFile|execSync|spawnSync|\bexec\(/, name)
    assert.doesNotMatch(source, /\u2014/, name)
  }
  const sink = read("sink.mjs")
  assert.match(sink, /detached: true/)
  assert.match(sink, /stdio: "ignore"/)
  assert.match(sink, /child\.unref\?*\.?\(\)/)
})

test("the ranking module imports nothing from the host", () => {
  assert.doesNotMatch(read("rank.mjs"), /^import /m)
})
