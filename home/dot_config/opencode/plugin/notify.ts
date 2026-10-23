// ~/.config/opencode/plugins/notify.ts
// OpenCode V2 notifier bridge: raises the terminal-native attention notifier when
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
// Outside tmux this plugin stays silent; OpenCode's own attention.sound covers
// that case. Inside tmux the shim withholds the visual flag while a focused
// client is already looking at the pane, and still plays the sound. See
// docs/notifications.md.
//
// V2 loads the Plugin.define entrypoint below and setup() subscribes to the public
// server event stream. fire() uses node:child_process and remains best-effort.
//
// Run OpenCode with --standalone (see the oc and oc2 aliases) so the plugin
// shares the live tmux pane's env. The background service does NOT simply lack
// TMUX/TMUX_PANE: it keeps whatever pane it was first started in, for as long as
// it lives (days). After a tmux server restart that pane id is gone, so the vars
// are set but stale and every fire targets a pane that no longer exists. The
// guard below cannot catch that, so the shim re-checks the pane against the live
// tmux server.
//
// No work logic lives here: enforcement, memory recall, and context injection are
// a separate, unmanaged local plugin (work.ts). This file stays generic.

import { Plugin } from "@opencode/plugin"
import { notificationGroup } from "./notify-filter.mjs"
import { fire } from "./notify-shim.mjs"

const IS_SHARED_SERVICE = process.argv.includes("--service")

// notify-filter.mjs maps attention events to groups after checking whether a
// session finished or a permission needs manual approval. Auto's TUI handler
// notifies after failed approvals through the same detached shim. The
// group selects its color and sound from ~/.config/notify/notify.yaml.
//
// Every name below was verified against OpenCode V2 by
// subscribing a probe plugin and driving a real session. Do not add names from
// the SDK type union without observing them: the union lists events this build
// never emits, which is how the question case stayed broken.
//
//   session.execution.succeeded  v2 turn finished. Child sessions are not a
//                                completion of the interactive root session.
//   permission.asked             v2 name for the same. Observed.
//   form.created                 v2. The question tool opens a form rather than
//                                emitting question.*. Auth forms also block.
//
// REMOVED because they do not exist on this build and never fired:
// question.asked, question.v2.asked, permission.v2.asked.
//
// Permission replies cancel only the matching request's in-flight check.
const EVENTS = new Set(["session.execution.succeeded", "permission.asked", "form.created"])

export default Plugin.define({
  id: "notify",

  // Subscribe to the async-iterable public event stream. Returns a disposer that
  // aborts the stream.
  //
  // Reconnects on unexpected stream end/error so a transient hiccup does not silence
  // notifications for the rest of the session, and logs the reason to stderr (visible
  // under --print-logs) so a real regression is distinguishable from a quiet, working
  // notifier. Bounded + backed off to avoid spinning; the retry budget resets after a
  // stream that stayed healthy for a while, so only rapid repeated failures give up.
  async setup(ctx): Promise<void | (() => void)> {
    const controller = new AbortController()
    let sequence = 0
    let notified = 0
    const permissions = new Map<string, number>()
    const completions = new Map<string, { obsolete: boolean }>()
    void (async () => {
      const MAX_RETRIES = 5
      let attempt = 0
      while (!controller.signal.aborted) {
        const startedAt = Date.now()
        try {
          for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
            if (event?.type === "permission.replied") {
              permissions.delete(`${event.data.sessionID}:${event.data.requestID}`)
              continue
            }
            if (!event || !EVENTS.has(event.type)) continue
            const current = ++sequence
            const sessionID = event.data?.sessionID ?? event.data?.form?.sessionID
            const completion = event.type === "session.execution.succeeded" ? { obsolete: false } : undefined
            const previous = completions.get(sessionID)
            if (previous) previous.obsolete = true
            if (completion) completions.set(sessionID, completion)
            const key = event.type === "permission.asked" ? `${event.data.sessionID}:${event.data.id}` : undefined
            if (key) permissions.set(key, current)
            const notify = (group: string | undefined) => {
              if (!group || controller.signal.aborted || current < notified || IS_SHARED_SERVICE) return
              if (key && permissions.get(key) !== current) return
              if (completion?.obsolete) return
              notified = current
              fire(group)
            }
            void notificationGroup(event, {
              getSession: (input) => ctx.session.get(input),
            }).then(notify).catch((err) => {
              if (!controller.signal.aborted) console.error("[notify] attention check failed:", err)
              if (event.type === "permission.asked") notify("opencode_permission")
            }).finally(() => {
              if (key && permissions.get(key) === current) permissions.delete(key)
              if (completion && completions.get(sessionID) === completion) completions.delete(sessionID)
            })
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
})
