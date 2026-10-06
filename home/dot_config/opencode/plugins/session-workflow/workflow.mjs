export function nextMode(agent) {
  if (agent === "build") return "plan"
  if (agent === "plan") return "auto"
  return "build"
}

export function shouldAutoApprove({ agent, action }) {
  return agent === "auto" && action !== "question"
}

export function rankInbox(entries) {
  return entries
    .map((entry, index) => ({ ...entry, index }))
    .sort((a, b) => {
      const level = (entry) => entry.pending || entry.attention ? 0 : entry.unread ? 1 : 2
      return level(a) - level(b) || b.viewed - a.viewed || a.index - b.index
    })
}
