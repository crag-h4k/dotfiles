// ~/.config/opencode/v2-plugins/demo/tui.tsx

import { homedir } from "node:os"
import { join } from "node:path"
import { Plugin } from "@opencode/plugin/tui"
import { runDemo } from "./demo.mjs"

export default Plugin.define({
  id: "dotfiles.demo",
  setup(context) {
    const directory = join(homedir(), ".config/opencode/demo")
    let running = false

    context.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "dotfiles.demo.run",
          title: "Demo: a small live task",
          group: "OpenCode setup",
          palette: true,
          slash: { name: "demo", arguments: true },
          async run(input) {
            if (running) {
              context.ui.toast.show({ message: "The demo is already running", variant: "info" })
              return
            }
            running = true
            try {
              await runDemo(context, input, directory)
            } catch (error) {
              context.ui.toast.show({
                title: "Demo failed",
                message: error instanceof Error ? error.message : String(error),
                variant: "error",
              })
            } finally {
              running = false
            }
          },
        },
      ],
    }))
  },
})
