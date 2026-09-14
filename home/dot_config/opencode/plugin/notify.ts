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

// Event -> notify group. The group decides the pane color and sound, so the three
// kinds of attention are told apart at a glance; appearance lives in
// ~/.config/notify/notify.yaml under `integrations:`.
//
// Every name below was verified against opencode2 v0.0.0-beta-19425 by
// subscribing a probe plugin and driving a real session. Do not add names from
// the SDK type union without observing them: the union lists events this build
// never emits, which is how the question case stayed broken.
//
//   session.idle                 v1 only. The v2 beta never emits it, despite the
//                                string being present in the binary.
//   session.execution.succeeded  v2 turn finished. This, not session.idle, is the
//                                real v2 completion event.
//   permission.updated           v1 name for a blocked approval prompt.
//   permission.asked             v2 name for the same. Observed.
//   form.created                 v2. The question tool does NOT emit a question.*
//                                event; it opens a form, and the event carries
//                                metadata.kind === "question". Auth forms reuse
//                                this and also block on the user, so both notify.
//
// REMOVED because they do not exist on this build and never fired:
// question.asked, question.v2.asked, permission.v2.asked.
//
// Deliberately NOT *.replied / *.rejected / form.cancelled: those fire when the
// user has just answered, so firing on them would fight the keypress-clear.
const GROUPS: ReadonlyMap<string, string> = new Map([
  ["session.idle", "opencode"],
  ["session.execution.succeeded", "opencode"],
  ["permission.updated", "opencode_permission"],
  ["permission.asked", "opencode_permission"],
  ["form.created", "opencode_question"],
])

// Fire the tmux notifier through the shared shim. Best-effort: gate on tmux and
// swallow every error so a notifier hiccup never disrupts the session. The shim
// reads TMUX_PANE from the inherited environment and self-guards, so no args are
// needed beyond the "fire" verb. Invoked via bash so it works even without the
// exec bit, and via child_process so it is runtime-agnostic (Bun and Node). The
// group argument selects the appearance, so the pane color says what OpenCode is
// waiting for.
//
// DETACHED ON PURPOSE, do not "simplify" this back to an awaited execFile. The
// attention events fire at the instant OpenCode tears down the execution, and a
// child left in OpenCode's process group is reaped along with it: the awaited
// execFile() died on SIGTERM (code=null, killed=false, empty stdout/stderr)
// before the shim ever reached tmux, so the pane never flagged. detached:true
// puts the shim in its own process group where the teardown cannot signal it,
// and unref() stops it holding the event loop open. The shim finishes in ~230ms,
// so this is fire-and-forget: nothing is awaited and no timeout is needed.
async function fire(group: string): Promise<void> {
  if (!process.env.TMUX || !process.env.TMUX_PANE) return
  try {
    const { spawn } = await import("node:child_process")
    const child = spawn("bash", [NOTIFY_SHIM, "fire", group], { detached: true, stdio: "ignore" })
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
            const group = event && GROUPS.get(event.type)
            if (group) await fire(group)
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
  // returned hooks. The generic `event` hook maps through the same table, so v1
  // gets the split groups too; it just only ever matches the v1 event names.
  async server(_input?: any) {
    return {
      event: async ({ event }: any) => {
        const group = event && GROUPS.get(event.type)
        if (group) await fire(group)
      },
    }
  },
}
