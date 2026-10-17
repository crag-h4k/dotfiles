// ~/.config/opencode/v2-plugins/demo/demo.mjs

export function demoModel(current, variants) {
  const variant = ["none", "minimal", "low", "medium", "high", "xhigh", "max"].find(
    (name) => variants.includes(name),
  )
  return { providerID: current.providerID, id: current.modelID, ...(variant ? { variant } : {}) }
}

export async function runDemo(context, input, directory) {
  const argument = (input ?? "").trim().replace(/^\/?demo(?:\s+|$)/, "").trim()
  if (argument) {
    context.ui.toast.show({ message: "Use /demo without arguments", variant: "warning" })
    return
  }
  const current = context.ui.model.current()
  if (!current) {
    context.ui.toast.show({ message: "Select a model before starting /demo", variant: "warning" })
    return
  }

  const location = { directory }
  const agents = await context.client.agent.list({ location })
  if (!agents.data.some((agent) => agent.id === "dotfiles-demo")) {
    throw new Error("The server has no dotfiles-demo agent. Apply the OpenCode component on the server first.")
  }
  const session = await context.client.session.create({
    title: "OpenCode demo",
    agent: "dotfiles-demo",
    location,
    model: demoModel(current, context.ui.model.variant.list()),
    permissions: [
      { action: "*", resource: "*", effect: "deny" },
      { action: "read", resource: "showcase.md", effect: "allow" },
      { action: "read", resource: `${directory}/showcase.md`, effect: "allow" },
      { action: "caveman_*", resource: "*", effect: "allow" },
    ],
  })
  context.ui.tabs.open(session.id)
  context.ui.router.navigate({ type: "session", sessionID: session.id })
  await context.client.session.prompt({
    sessionID: session.id,
    text: "Read showcase.md once. In at most 60 words, describe three features that make this setup useful. Stop after that answer.",
  })
  await context.client.session.wait({ sessionID: session.id })
  const finished = await context.client.session.get({ sessionID: session.id })
  const tokens = finished.tokens
  context.ui.toast.show({
    title: "Demo usage",
    message: `${tokens.input} input · ${tokens.output} output · ${tokens.reasoning} reasoning tokens`,
    variant: finished.outcome === "succeeded" ? "success" : "warning",
    sessionID: session.id,
    duration: 10_000,
  })
}
