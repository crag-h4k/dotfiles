export function nextMode(agent, auto) {
  if (agent === "plan") return { agent: "build", auto: true }
  if (agent === "build" && auto) return { agent: "build", auto: false }
  return { agent: "plan", auto: false }
}

export function shouldAutoApprove({ enabled, agent, action }) {
  return enabled && agent === "build" && action !== "question"
}

export function rankInbox(entries) {
  return entries
    .map((entry, index) => ({ ...entry, index }))
    .sort((a, b) => {
      const level = (entry) => entry.pending || entry.attention ? 0 : entry.unread ? 1 : 2
      return level(a) - level(b) || b.viewed - a.viewed || a.index - b.index
    })
}
