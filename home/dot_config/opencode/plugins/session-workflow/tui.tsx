/** @jsxImportSource @opentui/solid */
import { Plugin, usePlugin } from "@opencode/plugin/tui"
import { useTerminalDimensions } from "@opentui/solid"
import { createMemo, createSignal, For, Show } from "solid-js"
import { nextMode, rankInbox, shouldAutoApprove } from "./workflow.mjs"

const INBOX = "dotfiles.session-inbox"

export default Plugin.define({
  id: "dotfiles.session-workflow.tui",
  setup(context) {
    const [automatic, setAutomatic] = createSignal<Record<string, boolean>>({})
    const [selected, setSelected] = createSignal(0)
    let previous: { type: "home" } | { type: "session"; sessionID: string } = { type: "home" }

    const active = () => {
      const route = context.ui.router.current()
      return route.type === "plugin" && route.name === INBOX
    }

    const entries = () => rankInbox(context.ui.tabs.list().map((tab) => {
      const session = context.data.session.get(tab.sessionID)
      const location = session?.location
      return {
        ...tab,
        title: tab.title || session?.title || tab.sessionID.slice(0, 12),
        viewed: session?.time.viewed ?? session?.time.updated ?? 0,
        pending: (context.data.session.permission.list(tab.sessionID)?.length ?? 0) +
          (context.data.session.form.list(tab.sessionID, location)?.length ?? 0),
      }
    }))

    const close = () => context.ui.router.navigate(previous)
    const refresh = () => {
      for (const tab of context.ui.tabs.list()) {
        const location = context.data.session.get(tab.sessionID)?.location
        void context.data.session.permission.sync(tab.sessionID)
        void context.data.session.form.sync(tab.sessionID, location)
      }
    }

    const toggleInbox = () => {
      if (active()) return close()
      const route = context.ui.router.current()
      previous = route.type === "session" ? { type: "session", sessionID: route.sessionID } : { type: "home" }
      setSelected(0)
      refresh()
      context.ui.router.navigate({ type: "plugin", name: INBOX })
    }

    const cycle = async () => {
      const route = context.ui.router.current()
      if (route.type !== "session") return
      const id = route.sessionID
      const session = context.data.session.get(id) ?? await context.client.session.get({ sessionID: id })
      const mode = nextMode(session.agent ?? "build", automatic()[id] === true)
      if (mode.agent !== session.agent) {
        await context.client.session.switchAgent({ sessionID: id, agent: mode.agent })
        context.data.session.invalidate(id)
      }
      setAutomatic((current) => ({ ...current, [id]: mode.auto }))
      context.ui.toast.show({ message: mode.auto ? "Auto-approve" : mode.agent === "plan" ? "Plan" : "Build" })
    }

    const stopPermission = context.data.on("permission.asked", (event) => {
      const id = event.data.sessionID
      if (!automatic()[id]) return
      void (async () => {
        const session = context.data.session.get(id) ?? await context.client.session.get({ sessionID: id })
        if (!shouldAutoApprove({ enabled: automatic()[id], agent: session.agent ?? "build", action: event.data.action })) return
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
            { id: "dotfiles.inbox.toggle", title: "Toggle session inbox", bind: "<leader>t", palette: true, run: toggleInbox },
            { id: "dotfiles.inbox.down", bind: "down", enabled: active, run: () => setSelected((index) => Math.max(0, Math.min(index + 1, entries().length - 1))) },
            { id: "dotfiles.inbox.up", bind: "up", enabled: active, run: () => setSelected((index) => Math.max(index - 1, 0)) },
            { id: "dotfiles.inbox.open", bind: "return", enabled: active, run: () => {
              const rows = entries()
              const row = rows[Math.min(selected(), rows.length - 1)]
              if (row && context.ui.tabs.focus(row.sessionID)) {
                context.ui.router.navigate({ type: "session", sessionID: row.sessionID })
              }
            } },
            { id: "dotfiles.inbox.close", bind: "escape", enabled: active, run: close },
          ],
        }))
        return <></>
      },
    })

    const unregister = context.ui.router.register({
      name: INBOX,
      render: () => <Inbox entries={entries} selected={selected} automatic={automatic} />,
    })

    const removeStatus = context.ui.slot({
      append: "session.composer.top",
      render: ({ sessionID }) => <Show when={automatic()[sessionID] && context.data.session.get(sessionID)?.agent === "build"}>
        <text>Auto-approve · permission asks only</text>
      </Show>,
    })

    return () => {
      stopPermission()
      removeKeymap()
      unregister()
      removeStatus()
    }
  },
})

function Inbox(props: {
  entries: () => ReturnType<typeof rankInbox>
  selected: () => number
  automatic: () => Record<string, boolean>
}) {
  const context = usePlugin()
  const terminal = useTerminalDimensions()
  const visible = createMemo(() => {
    const rows = props.entries()
    const count = Math.max(1, terminal().height - 5)
    const start = Math.max(0, Math.min(props.selected() - Math.floor(count / 2), rows.length - count))
    return rows.slice(start, start + count).map((row, index) => ({ row, index: start + index }))
  })

  return (
    <box flexDirection="column" padding={1}>
      <text fg={context.theme.text.base}>Session inbox · ↑/↓ select · Enter open · Esc or Ctrl+G T hide</text>
      <For each={visible()}>{({ row, index }) => {
        const session = context.data.session.get(row.sessionID)
        const label = row.pending || row.attention ? "NEEDS INPUT" : row.unread ? "UNREAD" : "RECENT"
        const mode = props.automatic()[row.sessionID] && session?.agent === "build" ? " · AUTO" : ""
        return <text fg={context.theme.text.base}>
          {index === props.selected() ? ">" : " "} {label} · {row.title}{mode}
        </text>
      }}</For>
      <text fg={context.theme.text.base}>{props.entries().length} open tabs</text>
    </box>
  )
}
