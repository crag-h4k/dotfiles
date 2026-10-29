// ~/.config/opencode/v2-plugins/attention-tabs/controller.mjs
// The attention-tabs core: ranks tabs, plans sorting, toasts, jumps, the shared
// active set, and the optional tmux sink. It has no JSX and no Solid, so the
// plugin harness test drives it with a fake context. tui.tsx supplies the
// reactivity: it calls signature() inside a memo and changed() from an effect.
import { appendFileSync } from "node:fs"
import {
  KIND_LABEL,
  familyState,
  livePins,
  nextUrgent,
  planMoves,
  sinkState,
  topOther,
} from "./rank.mjs"
import { createSink } from "./sink.mjs"

export const DEFAULTS = Object.freeze({
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

const STORE_KEY = "attention-tabs.active"
const JUMP = "attention.jump"
const PAUSE = "attention.sort.pause"
const TOAST_MS = 8000
const TITLE_MAX = 40
const VARIANT = { permission: "warning", question: "info" }

const flag = (value, fallback) => (typeof value === "boolean" ? value : fallback)
const text = (value, fallback) => (typeof value === "string" && value.trim() !== "" ? value : fallback)

export function normalizeOptions(raw) {
  const options = raw && typeof raw === "object" ? raw : {}
  let jumpKey = DEFAULTS.jumpKey
  if (options.jumpKey === false || options.jumpKey === "" || options.jumpKey === "none") jumpKey = false
  else if (typeof options.jumpKey === "string") jumpKey = options.jumpKey
  return {
    sort: flag(options.sort, DEFAULTS.sort),
    jumpKey,
    toast: flag(options.toast, DEFAULTS.toast),
    banner: flag(options.banner, DEFAULTS.banner),
    tmuxSink: flag(options.tmuxSink, DEFAULTS.tmuxSink),
    notifierCommand: text(options.notifierCommand, DEFAULTS.notifierCommand),
    debounceMs: Number.isFinite(options.debounceMs) && options.debounceMs >= 0 ? options.debounceMs : DEFAULTS.debounceMs,
    activeTtlMs: Number.isFinite(options.activeTtlMs) && options.activeTtlMs > 0
      ? Math.max(1000, options.activeTtlMs)
      : DEFAULTS.activeTtlMs,
    debugLog: text(options.debugLog, undefined),
  }
}

const brief = (entries) => entries.map((entry) => `${entry.sessionID.slice(-6)}:${entry.rank}`)
const clip = (value, max) => (value.length > max ? `${value.slice(0, max - 1)}…` : value)

export function createController(ctx, rawOptions, deps = {}) {
  const options = normalizeOptions(rawOptions)
  const now = deps.now ?? (() => Date.now())
  const timers = deps.timers ?? { setTimeout, clearTimeout, setInterval, clearInterval }
  const untrack = deps.untrack ?? ((fn) => fn())
  const instanceId = deps.instanceId ?? `${process.pid}.${Math.random().toString(36).slice(2, 8)}`
  const sink = !options.tmuxSink
    ? null
    : "sink" in deps
      ? deps.sink
      : createSink({ command: options.notifierCommand, ...deps.sinkDeps })

  const heartbeatMs = Math.max(250, Math.floor(options.activeTtlMs / 3))
  const pruneMs = options.activeTtlMs * 4
  const unsubscribe = []
  const synced = new Set()
  let sortTimer
  let heartbeat
  let paused = false
  let disposed = false
  let published = { tab: undefined, at: 0 }

  const debug = (event, detail = {}) => {
    if (!options.debugLog) return
    try {
      appendFileSync(options.debugLog, `${JSON.stringify({ t: now(), id: instanceId, event, ...detail })}\n`)
    } catch {}
  }

  // Shared with every TUI through durable storage; each TUI owns only its own entry.
  const shared = (() => {
    try {
      if (typeof ctx.storage?.store !== "function") return undefined
      const [state, update] = ctx.storage.store(STORE_KEY, { initial: { tuis: {} } })
      return { state, update }
    } catch {
      return undefined
    }
  })()

  function snapshot() {
    const tabs = ctx.ui.tabs.list()
    const entries = tabs.map((tab) => {
      const family = new Set([tab.sessionID, ...(ctx.data.session.family(tab.sessionID) ?? [])])
      const members = [...family].map((id) => {
        const session = ctx.data.session.get(id)
        return {
          permissions: ctx.data.session.permission.list(id)?.length ?? 0,
          questions: ctx.data.session.form.list(id, session?.location)?.length ?? 0,
          updated: session?.time?.updated,
        }
      })
      const state = familyState({
        members,
        unread: tab.unread,
        updated: ctx.data.session.get(tab.sessionID)?.time?.updated,
      })
      return { sessionID: tab.sessionID, title: tab.title, ...state }
    })
    return { entries, activeID: tabs.find((tab) => tab.active)?.sessionID }
  }

  // Order independent, so the plugin's own moves never retrigger the effect.
  function signature() {
    const { entries, activeID } = snapshot()
    return JSON.stringify([
      activeID ?? null,
      entries.map((entry) => [entry.sessionID, entry.rank, entry.kind, entry.since]).sort((a, b) => (a[0] < b[0] ? -1 : 1)),
    ])
  }

  function pinnedTabs(activeID) {
    const pins = livePins(shared?.state, { now: now(), ttlMs: options.activeTtlMs, self: instanceId })
    if (activeID) pins.add(activeID)
    return pins
  }

  function publishActive(activeID, force = false) {
    if (!shared) return
    const at = now()
    if (!force && activeID === published.tab && at - published.at < heartbeatMs) return
    published = { tab: activeID, at }
    void shared
      .update((draft) => {
        if (!draft.tuis || typeof draft.tuis !== "object") draft.tuis = {}
        draft.tuis[instanceId] = { tab: activeID ?? null, at }
        for (const [id, entry] of Object.entries(draft.tuis)) {
          if (id !== instanceId && !(typeof entry?.at === "number" && at - entry.at < pruneMs)) delete draft.tuis[id]
        }
      })
      .catch(() => debug("publish-failed"))
  }

  function syncSession(id) {
    const location = ctx.data.session.get(id)?.location
    return Promise.all([ctx.data.session.permission.sync(id), ctx.data.session.form.sync(id, location)])
  }

  // Fetch the request lists for one session, then recompute: a tab can only rank
  // on data the client has. The calls start synchronously.
  function refresh(id) {
    let pending
    try {
      pending = syncSession(id)
    } catch (error) {
      pending = Promise.reject(error)
    }
    void pending.catch(() => debug("sync-failed", { id })).then(() => changed())
  }

  function syncNewTabs(entries) {
    for (const entry of entries) {
      if (synced.has(entry.sessionID)) continue
      synced.add(entry.sessionID)
      const family = new Set([entry.sessionID, ...(ctx.data.session.family(entry.sessionID) ?? [])])
      for (const id of family) refresh(id)
    }
  }

  function currentRoot() {
    const route = ctx.ui.router.current()
    return route?.type === "session" ? ctx.data.session.root(route.sessionID) : undefined
  }

  function notify(sessionID, kind, message) {
    if (!options.toast || disposed) return
    const root = ctx.data.session.root(sessionID)
    // The host adds its clickable Open action only for a different root.
    if (!root || root === currentRoot()) return
    debug("toast", { root, kind })
    ctx.ui.toast.show({ sessionID: root, message, variant: VARIANT[kind], duration: TOAST_MS })
  }

  function applySink({ entries, activeID }) {
    if (!sink) return
    const state = sinkState(entries, activeID)
    if (sink.apply(state)) debug("sink", { key: state.key })
  }

  function scheduleSort() {
    if (!options.sort || disposed) return
    if (sortTimer !== undefined) timers.clearTimeout(sortTimer)
    sortTimer = timers.setTimeout(runSort, options.debounceMs)
  }

  function leaderPending() {
    return typeof ctx.keymap?.pending === "function" && ctx.keymap.pending().length > 0
  }

  function runSort() {
    sortTimer = undefined
    if (disposed || !options.sort || paused) return
    if (leaderPending()) {
      sortTimer = timers.setTimeout(runSort, options.debounceMs)
      return
    }
    sortNow()
  }

  function sortNow() {
    const executed = []
    untrack(() => {
      const { entries, activeID } = snapshot()
      const pinned = pinnedTabs(activeID)
      const plan = planMoves(entries, pinned)
      if (options.debugLog && plan.length > 0) debug("sort", { order: brief(entries), active: activeID ?? null, pinned: [...pinned], plan })
      for (const move of plan) {
        if (pinned.has(move.id) || ctx.ui.tabs.move(move.id, move.index) === false) break
        executed.push(move)
      }
    })
    if (executed.length > 0) debug("move", { moves: executed })
    return executed
  }

  // Called from an effect whenever signature() changes, and from events.
  function changed() {
    if (disposed) return
    untrack(() => {
      const snap = snapshot()
      if (options.debugLog) debug("changed", { order: brief(snap.entries), active: snap.activeID ?? null })
      publishActive(snap.activeID)
      applySink(snap)
      syncNewTabs(snap.entries)
    })
    scheduleSort()
  }

  function bannerTarget(sessionID) {
    if (!options.banner) return undefined
    const { entries } = snapshot()
    // Completion still affects tab order and tint, but should not leave a banner behind.
    const top = topOther(entries.filter((entry) => entry.kind !== "completion"), ctx.data.session.root(sessionID))
    if (!top) return undefined
    const keys = ctx.keymap?.shortcuts?.(JUMP) ?? []
    const hint = keys[0] ? ` (click or ${keys[0]})` : " (click)"
    const title = clip(top.title || top.sessionID, TITLE_MAX)
    return { sessionID: top.sessionID, kind: top.kind, title, label: `${KIND_LABEL[top.kind]}: ${title}${hint}` }
  }

  function focus(sessionID) {
    return ctx.ui.tabs.focus(sessionID)
  }

  function jump() {
    const { entries, activeID } = untrack(snapshot)
    const next = nextUrgent(entries, activeID)
    if (!next) return undefined
    debug("jump", { to: next.sessionID })
    focus(next.sessionID)
    return next.sessionID
  }

  function togglePause() {
    if (!options.sort) {
      ctx.ui.toast.show({ message: "Attention sorting is off. Set the sort option to true to use it.", variant: "info" })
      return
    }
    paused = !paused
    ctx.ui.toast.show({ message: paused ? "Attention sorting paused" : "Attention sorting resumed", variant: "info" })
    if (!paused) scheduleSort()
  }

  function commands() {
    return [
      {
        id: JUMP,
        title: "Jump to the tab that needs attention",
        description: "Focus the most urgent other tab; repeat to step through the rest.",
        group: "Tabs",
        palette: true,
        slash: { name: "attention-jump" },
        bind: options.jumpKey,
        enabled: () => ctx.ui.tabs.enabled(),
        run: () => { jump() },
      },
      {
        id: PAUSE,
        title: "Pause or resume attention tab sorting",
        group: "Tabs",
        palette: true,
        slash: { name: "attention-sort" },
        bind: false,
        enabled: () => ctx.ui.tabs.enabled(),
        run: () => { togglePause() },
      },
    ]
  }

  function start() {
    const on = (type, handler) => {
      unsubscribe.push(ctx.data.on(type, (event) => { if (!disposed) handler(event) }))
    }
    on("permission.asked", (event) => {
      const { sessionID, action } = event.data
      refresh(sessionID)
      notify(sessionID, "permission", `${KIND_LABEL.permission}${action ? `: ${action}` : ""}`)
    })
    on("permission.replied", (event) => refresh(event.data.sessionID))
    on("form.created", (event) => {
      const { sessionID, title } = event.data.form
      refresh(sessionID)
      notify(sessionID, "question", `${KIND_LABEL.question}${title ? `: ${clip(title, 80)}` : ""}`)
    })
    on("form.replied", (event) => refresh(event.data.sessionID))
    on("form.cancelled", (event) => refresh(event.data.sessionID))
    on("session.execution.succeeded", () => changed())
    on("session.viewed", () => changed())
    // The heartbeat keeps this TUI's active-tab entry alive, and re-plans so a
    // tab pinned by an entry that has since expired can finally move.
    heartbeat = timers.setInterval(() => {
      if (disposed) return
      const activeID = untrack(() => ctx.ui.tabs.list().find((tab) => tab.active)?.sessionID)
      publishActive(activeID, true)
      if (options.debugLog) {
        const raw = untrack(() => ctx.ui.tabs.list().map((tab) =>
          `${tab.sessionID.slice(-6)}:${tab.busy ? "busy" : ""}${tab.attention ? "+attn" : ""}${tab.unread ? `+${tab.unread}` : ""}`))
        const entries = Object.entries(shared?.state?.tuis ?? {}).map(([id, entry]) => `${id}=${entry?.tab ? String(entry.tab).slice(-6) : "none"}@${entry?.at}`)
        debug("tick", { active: activeID ?? null, pins: [...pinnedTabs(activeID)], tabs: raw, shared: entries })
      }
      scheduleSort()
    }, heartbeatMs)
    debug("start", { options: { ...options }, sink: Boolean(sink?.available?.() ?? sink) })
  }

  function dispose() {
    if (disposed) return
    disposed = true
    for (const stop of unsubscribe.splice(0)) stop()
    if (sortTimer !== undefined) timers.clearTimeout(sortTimer)
    if (heartbeat !== undefined) timers.clearInterval(heartbeat)
    sortTimer = heartbeat = undefined
    if (shared) {
      void shared
        .update((draft) => { if (draft.tuis) delete draft.tuis[instanceId] })
        .catch(() => {})
    }
    debug("dispose")
  }

  return {
    options,
    start,
    dispose,
    snapshot,
    signature,
    changed,
    sortNow,
    bannerTarget,
    focus,
    jump,
    commands,
    togglePause,
    isPaused: () => paused,
    sinkAvailable: () => Boolean(sink && (typeof sink.available === "function" ? sink.available() : true)),
  }
}
