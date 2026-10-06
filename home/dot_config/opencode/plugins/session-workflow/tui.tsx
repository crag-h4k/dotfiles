/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui"
import { nextMode, shouldAutoApprove } from "./workflow.mjs"

export default Plugin.define({
  id: "dotfiles.session-workflow.tui",
  setup(context) {
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
      void (async () => {
        const session = await context.client.session.get({ sessionID: id })
        if (!shouldAutoApprove({ agent: session.agent ?? "build", action: event.data.action })) return
        await context.client.permission.reply({ sessionID: id, requestID: event.data.id, decision: "once" })
      })().catch(() => {
        context.ui.toast.show({ message: "Auto-approval failed; answer the permission prompt manually", variant: "warning" })
      })
    })

    const removeKeymap = context.ui.slot({
      append: "app",
      render: () => {
        context.keymap.layer(() => ({
          mode: "global",
          priority: 10,
          commands: [
            { id: "dotfiles.mode.cycle", title: "Cycle Build / Plan / Auto", bind: "shift+tab", run: cycle },
          ],
        }))
        return <></>
      },
    })

    return () => {
      stopPermission()
      removeKeymap()
    }
  },
})
