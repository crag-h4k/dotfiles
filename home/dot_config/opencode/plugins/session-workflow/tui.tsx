/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui"
import { createEffect } from "solid-js"
import { nextMode, reorderTabs, shouldAutoApprove } from "./workflow.mjs"

export default Plugin.define({
  id: "dotfiles.session-workflow.tui",
  setup(context) {
    let timer: ReturnType<typeof setTimeout> | undefined
    const synced = new Set<string>()

    const reorder = () => {
      const tabs = context.ui.tabs.list()
      const entries = tabs.map((tab) => {
        const session = context.data.session.get(tab.sessionID)
        return {
          ...tab,
          viewed: session?.time.viewed ?? session?.time.updated ?? 0,
          pending: (context.data.session.permission.list(tab.sessionID)?.length ?? 0) +
            (context.data.session.form.list(tab.sessionID, session?.location)?.length ?? 0),
        }
      })
      reorderTabs(entries, (id, index) => context.ui.tabs.move(id, index))
    }

    const schedule = () => {
      if (timer) return
      timer = setTimeout(() => {
        timer = undefined
        reorder()
      }, 0)
    }

    const syncAttention = (id: string) => {
      if (!context.ui.tabs.list().some((tab) => tab.sessionID === id)) return
      const location = context.data.session.get(id)?.location
      void Promise.all([
        context.data.session.permission.sync(id),
        context.data.session.form.sync(id, location),
      ]).then(schedule, () => {
        console.warn("session-workflow: tab attention refresh failed")
        schedule()
      })
    }

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
      syncAttention(id)
      if (event.data.action === "question") return
      void (async () => {
        const session = await context.client.session.get({ sessionID: id })
        if (!shouldAutoApprove({ agent: session.agent ?? "build", action: event.data.action })) return
        await context.client.permission.reply({ sessionID: id, requestID: event.data.id, decision: "once" })
      })().catch(() => {
        context.ui.toast.show({ message: "Auto-approval failed; answer the permission prompt manually", variant: "warning" })
      })
    })

    const stopEvents = [
      context.data.on("permission.replied", (event) => syncAttention(event.data.sessionID)),
      context.data.on("form.created", (event) => syncAttention(event.data.form.sessionID)),
      context.data.on("form.replied", (event) => syncAttention(event.data.sessionID)),
      context.data.on("form.cancelled", (event) => syncAttention(event.data.sessionID)),
      context.data.on("session.execution.succeeded", schedule),
      context.data.on("session.viewed", schedule),
    ]

    const removeKeymap = context.ui.slot({
      append: "app",
      render: () => {
        createEffect(() => {
          for (const tab of context.ui.tabs.list()) {
            if (!synced.has(tab.sessionID)) {
              synced.add(tab.sessionID)
              syncAttention(tab.sessionID)
            }
          }
          schedule()
        })
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
      stopEvents.forEach((stop) => stop())
      if (timer) clearTimeout(timer)
      removeKeymap()
    }
  },
})
