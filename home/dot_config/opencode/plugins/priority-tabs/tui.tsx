/** @jsxImportSource @opentui/solid */
import { Plugin } from "@opencode/plugin/tui"
import { createEffect } from "solid-js"
import { reorderTabs } from "./priority.mjs"

// Inactive until native tab moves are verified not to change focus on macOS.
export default Plugin.define({
  id: "dotfiles.priority-tabs.tui",
  setup(context) {
    let timer: ReturnType<typeof setTimeout> | undefined
    const synced = new Set<string>()

    const reorder = () => {
      const entries = context.ui.tabs.list().map((tab) => {
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
        console.warn("priority-tabs: attention refresh failed")
        schedule()
      })
    }

    const stopEvents = [
      context.data.on("permission.asked", (event) => syncAttention(event.data.sessionID)),
      context.data.on("permission.replied", (event) => syncAttention(event.data.sessionID)),
      context.data.on("form.created", (event) => syncAttention(event.data.form.sessionID)),
      context.data.on("form.replied", (event) => syncAttention(event.data.sessionID)),
      context.data.on("form.cancelled", (event) => syncAttention(event.data.sessionID)),
      context.data.on("session.execution.succeeded", schedule),
      context.data.on("session.viewed", schedule),
    ]

    const removeSlot = context.ui.slot({
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
        return <></>
      },
    })

    return () => {
      stopEvents.forEach((stop) => stop())
      if (timer) clearTimeout(timer)
      removeSlot()
    }
  },
})
