// ~/.config/opencode/plugin/notify.ts
// Generic notifier bridge: raises the terminal-native attention notifier when
// OpenCode wants attention, so an idle session or a pending permission prompt
// flags its tmux pane. This is the OpenCode analog of the shell process notifier
// and the Claude/Codex notify hooks.
//
// It shells out to ~/.config/notify/opencode-events.sh (which sources
// ~/.config/notify/lib.sh and fires the 'opencode' group). Appearance/sound for
// that group live in ~/.config/notify/notify.yaml; tmux renders the per-pane
// color via ~/.tmux/conf.d/notify.conf. The flag clears on the next keypress or
// click in the pane (tmux handles that), so this plugin only ever fires.
//
// DUAL-TARGET by design. One ~/.config/opencode/ dir is shared by v1 (`opencode`,
// 1.18.x, Bun) and v2 (`opencode2`, beta, Node), and the two have incompatible
// plugin contracts, so this single default export carries both:
//   - v2 loads { id, setup }: setup() subscribes to ctx.event (an async iterable
//     of server events) and fires on session.idle / permission.asked.
//   - v1 loads { server }: server() returns the classic { event } hook and fires
//     on session.idle / permission.updated.
// Each path feature-detects its runtime (v2 setup no-ops when ctx.event is absent),
// so exactly one fires per binary and a missing API never throws. define() from the
// SDK is only a type-level identity helper, so we export the plain object directly;
// that avoids depending on the v1-pinned plugin package resolving under the v2
// binary. fire() uses node:child_process (not Bun's $) so it works on both runtimes.
//
// v2 note: run opencode2 with --standalone (see the oc2 alias) so the plugin
// shares the live tmux pane's env. The background service does NOT simply lack
// TMUX/TMUX_PANE: it keeps whatever pane it was first started in, for as long as
// it lives (days). After a tmux server restart that pane id is gone, so the vars
// are set but stale and every fire targets a pane that no longer exists. The
// guard below cannot catch that, so the shim re-checks the pane against the live
// tmux server.
//
// No work logic lives here: enforcement, memory recall, and context injection are
// a separate, unmanaged local plugin (work.ts). This file stays generic.

const NOTIFY_SHIM = `${process.env.HOME ?? ""}/.config/notify/opencode-events.sh`

// Events that warrant attention:
//   session.idle                    - turn finished, waiting on the user (v1, and the
//                                     installed v2 beta SDK event union).
//   session.execution.succeeded     - the v2 dev-branch completion event; ahead of the
//                                     pinned beta, so listed for forward-compat.
//   permission.updated              - a tool is blocked on an approval prompt (v1 name).
//   permission.asked / .v2.asked    - the same, under the v2 (and v2-namespaced) names.
//   question.asked / .v2.asked      - the agent is asking the user a question and is
//                                     blocked on the answer (the opencode analog of an
//                                     interactive prompt). v2 emits question.asked; this
//                                     was the missing case that never flagged the pane.
// Deliberately NOT *.replied / *.rejected: those fire when the user just answered, so
// firing on them would fight the keypress-clear.
const ATTENTION: ReadonlySet<string> = new Set([
  "session.idle",
  "session.execution.succeeded",
  "permission.updated",
  "permission.asked",
  "permission.v2.asked",
  "question.asked",
  "question.v2.asked",
])

// Fire the tmux notifier through the shared shim. Best-effort: gate on tmux and
// swallow every error so a notifier hiccup never disrupts the session. The shim
// reads TMUX_PANE from the inherited environment and self-guards, so no args are
// needed beyond the "fire" verb. Invoked via bash so it works even without the
// exec bit, and via child_process so it is runtime-agnostic (Bun and Node).
//
// DETACHED ON PURPOSE, do not "simplify" this back to an awaited execFile. The
// attention events fire at the instant OpenCode tears down the execution, and a
// child left in OpenCode's process group is reaped along with it: the awaited
// execFile() died on SIGTERM (code=null, killed=false, empty stdout/stderr)
// before the shim ever reached tmux, so the pane never flagged. detached:true
// puts the shim in its own process group where the teardown cannot signal it,
// and unref() stops it holding the event loop open. The shim finishes in ~230ms,
// so this is fire-and-forget: nothing is awaited and no timeout is needed.
async function fire(): Promise<void> {
  if (!process.env.TMUX || !process.env.TMUX_PANE) return
  try {
    const { spawn } = await import("node:child_process")
    const child = spawn("bash", [NOTIFY_SHIM, "fire"], { detached: true, stdio: "ignore" })
    child.on("error", () => {})
    child.unref()
  } catch {
    /* notifier is best-effort */
  }
}

export default {
  id: "notify",

  // v2 (opencode2): subscribe to the async-iterable public event stream. No-ops on
  // any runtime that does not hand us ctx.event.subscribe (i.e. v1), where server()
  // below carries the load instead. Returns a disposer that aborts the stream.
  //
  // Reconnects on unexpected stream end/error so a transient hiccup does not silence
  // notifications for the rest of the session, and logs the reason to stderr (visible
  // under --print-logs) so a real regression is distinguishable from a quiet, working
  // notifier. Bounded + backed off to avoid spinning; the retry budget resets after a
  // stream that stayed healthy for a while, so only rapid repeated failures give up.
  async setup(ctx: any): Promise<void | (() => void)> {
    if (!ctx || !ctx.event || typeof ctx.event.subscribe !== "function") return
    const controller = new AbortController()
    void (async () => {
      const MAX_RETRIES = 5
      let attempt = 0
      while (!controller.signal.aborted) {
        const startedAt = Date.now()
        try {
          for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
            if (event && ATTENTION.has(event.type)) await fire()
          }
          if (controller.signal.aborted) break
          console.error("[notify] event stream ended; reconnecting")
        } catch (err) {
          if (controller.signal.aborted) break
          console.error("[notify] event stream error; reconnecting:", err)
        }
        if (Date.now() - startedAt > 60_000) attempt = 0 // healthy run resets the budget
        if (attempt++ >= MAX_RETRIES) {
          console.error(`[notify] giving up after ${MAX_RETRIES + 1} event-stream attempts`)
          break
        }
        await new Promise((r) => setTimeout(r, Math.min(1000 * 2 ** attempt, 15000)))
      }
    })()
    return () => controller.abort()
  },

  // v1 (opencode): the legacy host calls default.server(input) and uses the
  // returned hooks. The generic `event` hook matches the same attention events.
  async server(_input?: any) {
    return {
      event: async ({ event }: any) => {
        if (event && ATTENTION.has(event.type)) await fire()
      },
    }
  },
}
