/** @jsxImportSource @opentui/solid */
import type { usePlugin } from "@opencode/plugin/tui"
import type { TextRenderable } from "@opentui/core"
import { createSignal, For, onCleanup, onMount } from "solid-js"

type Context = ReturnType<typeof usePlugin>
type Variant = "literal" | "dynamic" | "leading" | "padded" | "fixed" | "split" | "joined"

const VARIANTS: { id: Variant; label: string }[] = [
  { id: "literal", label: "Literal, padded" },
  { id: "dynamic", label: "Dynamic, alone" },
  { id: "leading", label: "Leading space" },
  { id: "padded", label: "Both-side spaces" },
  { id: "fixed", label: "Fixed 4 cells" },
  { id: "split", label: "Separate icon node" },
  { id: "joined", label: "Joined styled text" },
]

function Diagnostics(props: { context: Context }) {
  const context = props.context
  const nodes = new Map<string, TextRenderable>()
  const [sizes, setSizes] = createSignal<Record<string, string>>({})
  const [capabilities, setCapabilities] = createSignal(context.renderer.capabilities)
  let timer: ReturnType<typeof setTimeout> | undefined

  function measure() {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => {
      setSizes(Object.fromEntries([...nodes].map(([id, node]) => [
        id, `${node.width}/${node.scrollWidth}`,
      ])))
      setCapabilities(context.renderer.capabilities)
    }, 100)
  }

  onMount(() => {
    measure()
    context.renderer.on("resize", measure)
    context.renderer.on("capabilities", measure)
  })
  onCleanup(() => {
    if (timer) clearTimeout(timer)
    context.renderer.off("resize", measure)
    context.renderer.off("capabilities", measure)
  })

  function sample(glyph: string, variant: Variant) {
    const id = `${variant}:${glyph}`
    const ref = (node: TextRenderable) => nodes.set(id, node)
    const style = { fg: "#bd93f9", bg: "#44475a", wrapMode: "none" as const }
    if (variant === "literal") {
      return glyph === "󰉋"
        ? <text ref={ref} {...style}>{" 󰉋 "}</text>
        : <text ref={ref} {...style}>{" 󰚩 "}</text>
    }
    if (variant === "split") {
      return (
        <box flexDirection="row" flexShrink={0}>
          <text ref={ref} {...style}>{` ${glyph}`}</text>
          <text {...style}>{" label "}</text>
        </box>
      )
    }
    if (variant === "joined") {
      return (
        <text ref={ref} {...style} flexShrink={0}>
          <span>{` ${glyph} `}</span><span style={{ fg: "#f8f8f2" }}>{"label "}</span>
        </text>
      )
    }
    if (variant === "fixed") {
      return <text ref={ref} {...style} width={4} minWidth={4} flexShrink={0}>{` ${glyph} `}</text>
    }
    const value = variant === "leading" ? ` ${glyph}` : variant === "padded" ? ` ${glyph} ` : glyph
    return <text ref={ref} {...style}>{value}</text>
  }

  const muted = context.theme.text.subdued
  return (
    <box flexDirection="column" padding={1} gap={1}>
      <text>OpenCode terminal diagnostics</text>
      <text fg={muted}>Local rendering only. Folder and robot use the same style.</text>
      <text fg={muted}>
        {`Width: ${context.renderer.widthMethod}; terminal: ${capabilities()?.terminal.name || "unknown"}; mux: ${capabilities()?.multiplexer || "none"}`}
      </text>
      <text fg={muted}>
        {`OSC66: ${Boolean(capabilities()?.explicit_width)}; Unicode: ${capabilities()?.unicode || "unknown"}; sync: ${Boolean(capabilities()?.sync)}; remote: ${Boolean(capabilities()?.remote)}`}
      </text>
      <box flexDirection="column">
        <box flexDirection="row">
          <text width={22}>Variant</text><text width={25}>Folder (width/scroll)</text><text>Robot (width/scroll)</text>
        </box>
        <For each={VARIANTS}>
          {(variant) => (
            <box flexDirection="row">
              <text width={22}>{variant.label}</text>
              <For each={["󰉋", "󰚩"]}>
                {(glyph) => (
                  <box flexDirection="row" width={25} gap={1}>
                    {sample(glyph, variant.id)}
                    <text fg={muted}>{sizes()[`${variant.id}:${glyph}`] ?? "…"}</text>
                  </box>
                )}
              </For>
            </box>
          )}
        </For>
      </box>
      <text>{"Other glyphs:    󰥔 󰍛 󰊤 󰓻"}</text>
      <text fg={muted}>Compare the same rows outside and inside tmux. Esc closes.</text>
    </box>
  )
}

export function showDiagnostics(context: Context): void {
  context.ui.dialog.show(() => <Diagnostics context={context} />)
  context.ui.dialog.set({ size: "xlarge", centered: true })
}
