import { Agent, Plugin } from "@opencode/plugin"

export default Plugin.define({
  id: "dotfiles.session-workflow",
  async setup(context) {
    await context.agent.transform((editor) => {
      editor.update("auto", (agent) => { agent.name = Agent.Name.make("Auto") })
    })
  },
})
