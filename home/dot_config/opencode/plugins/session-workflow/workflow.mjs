export function nextMode(agent) {
  if (agent === "build") return "plan"
  if (agent === "plan") return "auto"
  return "build"
}

export function shouldAutoApprove({ agent, action }) {
  return agent === "auto" && action !== "question"
}

export function rankTabs(entries) {
  return entries
    .map((entry, index) => ({ ...entry, index }))
    .sort((a, b) => {
      const level = (entry) => entry.pending || entry.attention ? 0 : entry.unread ? 1 : 2
      return level(a) - level(b) || b.viewed - a.viewed || a.index - b.index
    })
}

export function reorderTabs(entries, move) {
  const order = entries.map((entry) => entry.sessionID)
  const ranked = rankTabs(entries)
  ranked.forEach((entry, index) => {
    const current = order.indexOf(entry.sessionID)
    if (current === index || move(entry.sessionID, index) === false) return
    order.splice(current, 1)
    order.splice(index, 0, entry.sessionID)
  })
  return order
}
