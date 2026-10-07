// ~/.config/opencode/v2-plugins/agent-catalog/tui.tsx

import { Plugin } from "@opencode/plugin/tui"
import { agentDetails, agentOption, compareAgents } from "./catalog.mjs"

export default Plugin.define({
  id: "dotfiles.agent-catalog",
  setup(context) {
    const location = context.location ?? context.data.location.default()

    async function showCatalog() {
      try {
        await context.data.location.agent.sync(location)
      } catch {
        await context.ui.dialog.alert({
          title: "Agent catalog unavailable",
          message: "OpenCode could not load configured agents for this location.",
        })
        return
      }

      const agents = [...(context.data.location.agent.list(location) ?? [])].sort(compareAgents)
      if (agents.length === 0) {
        await context.ui.dialog.alert({
          title: "Agent catalog",
          message: "No configured agents are available for this location.",
        })
        return
      }

      const selected = await context.ui.dialog.select({
        title: `Agent catalog (${agents.length})`,
        options: agents.map(agentOption),
        search: (query, options) => {
          const needle = query.toLowerCase()
          return options.filter((option) =>
            `${option.title} ${option.description ?? ""}`.toLowerCase().includes(needle),
          )
        },
      })
      const agent = agents.find((candidate) => candidate.id === selected)
      if (!agent) return

      await context.ui.dialog.alert({
        title: agent.id,
        message: agentDetails(agent),
      })
    }

    context.keymap.layer(() => ({
      mode: "global",
      priority: 10,
      commands: [
        {
          id: "dotfiles.agent-catalog.open",
          title: "Browse configured agents",
          group: "OpenCode",
          palette: true,
          slash: { name: "subagents", aliases: ["subagents-catalog"], arguments: false },
          suggested: true,
          run: showCatalog,
        },
      ],
    }))
  },
})
