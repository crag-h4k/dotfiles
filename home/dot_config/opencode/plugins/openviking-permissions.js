// home/dot_config/opencode/plugins/openviking-permissions.js
import { Plugin } from "@opencode/plugin"

const rules = [
  { action: "openviking_*", resource: "*", effect: "allow" },
  { action: "skill", resource: "openviking-*", effect: "allow" },
  { action: "skill", resource: "ov-experience-memory", effect: "allow" },
]

export default Plugin.define({
  id: "dotfiles.openviking-permissions",
  async setup(ctx) {
    await ctx.agent.transform((editor) => {
      for (const agent of editor.list()) {
        editor.update(agent.id, (draft) => {
          const permissions = draft.permissions ?? []
          const tail = permissions.slice(-rules.length)
          const current = tail.length === rules.length && tail.every((rule, index) =>
            rule.action === rules[index].action &&
            rule.resource === rules[index].resource &&
            rule.effect === rules[index].effect)
          if (!current) draft.permissions = [...permissions, ...rules.map((rule) => ({ ...rule }))]
        })
      }
    })
  },
})
