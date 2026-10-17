/** @jsxImportSource @opentui/solid */
// home/dot_config/opencode/plugins/session-workflow/tui.tsx
import { Plugin } from "@opencode/plugin/tui"
import { nextMode, shouldAutoApprove } from "./workflow.mjs"
import { fire } from "../../plugin/notify-shim.mjs"

export default Plugin.define({
  id: "dotfiles.session-workflow.tui",
  setup(context) {
    let disposed = false
    const approvals = new Map<string, { sessionID: string; answered: boolean; superseded: boolean }>()
    const cycle = async () => {
      const route = context.ui.router.current()
      if (route.type !== "session") return
      const id = route.sessionID
      const session = await context.client.session.get({ sessionID: id })
      const agent = nextMode(session.agent ?? "build")
      await context.client.session.switchAgent({ sessionID: id, agent })
      context.data.session.invalidate(id)
      context.ui.toast.show({ message: agent === "auto" ? "Auto" : agent === "plan" ? "Plan" : "Build" })
    }

    const stopPermission = context.data.on("permission.asked", (event) => {
      const id = event.data.sessionID
      if (event.data.action === "question") return
      const key = `${id}:${event.data.id}`
      if (approvals.has(key)) return
      const request = { sessionID: id, answered: false, superseded: false }
      approvals.set(key, request)
      void (async () => {
        const session = await context.client.session.get({ sessionID: id })
        if (!shouldAutoApprove({ agent: session.agent ?? "build", action: event.data.action })) return
        await context.client.permission.reply({ sessionID: id, requestID: event.data.id, decision: "once" })
      })().catch(async () => {
        // Another client may have answered while this client's approval failed.
        try {
          const pending = await context.client.permission.list({ sessionID: id })
          if (!pending.some((request) => request.id === event.data.id)) return
        } catch {
          // If the request cannot be checked, keep the manual attention fallback.
        }
        if (disposed || request.answered || request.superseded) return
        context.ui.toast.show({ message: "Auto-approval failed; answer the permission prompt manually", variant: "warning" })
        const route = context.ui.router.current()
        if (route.type === "session" && context.data.session.root(id) === context.data.session.root(route.sessionID)) {
          fire("opencode_permission")
        }
      }).finally(() => {
        approvals.delete(key)
      })
    })
    const stopReply = context.data.on("permission.replied", (event) => {
      const request = approvals.get(`${event.data.sessionID}:${event.data.requestID}`)
      if (request) request.answered = true
    })
    const stopForm = context.data.on("form.created", (event) => {
      const root = context.data.session.root(event.data.form.sessionID)
      for (const request of approvals.values()) {
        if (context.data.session.root(request.sessionID) === root) request.superseded = true
      }
    })

    const removeKeymap = context.ui.slot({
      append: "app",
      render: () => {
        context.keymap.layer(() => ({
          mode: "global",
          priority: 10,
          commands: [
            {
              id: "dotfiles.mode.cycle",
              title: "Cycle Build / Plan / Auto",
              bind: "shift+tab",
              run: () => context.ui.router.current().type === "session" ? cycle() : false,
            },
          ],
        }))
        return <></>
      },
    })

    return () => {
      disposed = true
      stopPermission()
      stopReply()
      stopForm()
      approvals.clear()
      removeKeymap()
    }
  },
})
