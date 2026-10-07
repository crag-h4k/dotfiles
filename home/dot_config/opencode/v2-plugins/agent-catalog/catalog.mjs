// ~/.config/opencode/v2-plugins/agent-catalog/catalog.mjs

const DESCRIPTION_LIMIT = 140

const MODE_ORDER = {
  primary: 0,
  all: 1,
  subagent: 2,
}

function oneLine(value) {
  return value.replaceAll(/\s+/g, " ").trim()
}

export function summarizeDescription(description) {
  if (!description) return undefined
  const summary = oneLine(description)
  if (summary.length <= DESCRIPTION_LIMIT) return summary
  return `${summary.slice(0, DESCRIPTION_LIMIT - 1).trimEnd()}…`
}

export function modelLabel(agent) {
  if (!agent.model) return "inherits session model"
  const model = `${agent.model.providerID}/${agent.model.id}`
  return agent.model.variant ? `${model}#${agent.model.variant}` : model
}

export function agentCategory(agent) {
  if (agent.hidden) return "Hidden"
  if (agent.mode === "primary") return "Primary"
  if (agent.mode === "all") return "Primary and subagent"
  return "Subagent"
}

export function compareAgents(left, right) {
  if (left.hidden !== right.hidden) return left.hidden ? 1 : -1
  const mode = MODE_ORDER[left.mode] - MODE_ORDER[right.mode]
  if (mode !== 0) return mode
  return left.id.localeCompare(right.id)
}

export function agentOption(agent) {
  const title = agent.name === agent.id ? agent.id : `${agent.name} (${agent.id})`
  const details = [agent.mode, modelLabel(agent), summarizeDescription(agent.description)].filter(Boolean)
  return {
    title,
    value: agent.id,
    description: details.join(" · "),
    category: agentCategory(agent),
  }
}

export function agentDetails(agent) {
  const description = oneLine(agent.description ?? "No description configured.")
  return [
    `Mode: ${agent.mode}`,
    `Visibility: ${agent.hidden ? "hidden" : "visible"}`,
    `Model: ${modelLabel(agent)}`,
    `Permissions: ${agent.permissions.length} rules`,
    "",
    description,
  ].join("\n")
}
