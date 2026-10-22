/** @jsxImportSource @opentui/solid */
// ~/.config/opencode/v2-plugins/attention-tabs/tui.tsx
// Tab-aware attention for OpenCode V2: ranked tab order, jump, toast, banner, and
// an optional tmux tint. The logic lives in controller.mjs; this file supplies the
// Solid reactivity and the banner element.
import { Plugin } from "@opencode/plugin/tui"
import type { Context } from "@opencode/plugin/tui/context"
import { createEffect, createMemo, on, Show, untrack } from "solid-js"
import { createController } from "./controller.mjs"

const ROLE = { permission: "warning", error: "error", question: "info", completion: "success" } as const

function bannerColor(theme: Context["theme"], kind: keyof typeof ROLE) {
  return theme.text.feedback[ROLE[kind]].base
}

export default Plugin.define({
  id: "dotfiles.attention-tabs",
  setup(context) {
    const ctl = createController(context, context.options, { untrack })
    ctl.start()

    const removers = [
      // A render in the app slot gives the effect a reactive owner. It tracks only
      // an order-independent signature, so the plugin's own moves never retrigger it.
      context.ui.slot({
        append: "app",
        render: () => {
          const signature = createMemo(() => ctl.signature())
          createEffect(on(signature, () => ctl.changed()))
          return <></>
        },
      }),
    ]

    if (ctl.options.banner) {
      removers.push(
        context.ui.slot({
          append: "session.composer.top",
          render: (input) => {
            const target = createMemo(() => ctl.bannerTarget(input.sessionID), undefined, {
              equals: (a, b) => a?.sessionID === b?.sessionID && a?.label === b?.label,
            })
            return (
              <Show when={target()}>
                {(item) => (
                  <box flexShrink={0} paddingLeft={1} onMouseUp={() => ctl.focus(item().sessionID)}>
                    <text wrapMode="none" fg={bannerColor(context.theme, item().kind)}>{item().label}</text>
                  </box>
                )}
              </Show>
            )
          },
        }),
      )
    }

    context.keymap.layer(() => ({ mode: "global", priority: 10, commands: ctl.commands() }))

    return () => {
      for (const remove of removers) remove()
      ctl.dispose()
    }
  },
})
