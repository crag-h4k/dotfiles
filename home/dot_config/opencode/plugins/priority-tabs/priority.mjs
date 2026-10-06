export function rankTabs(entries) {
  return entries
    .map((entry, index) => ({ ...entry, index }))
    .sort((a, b) => {
      const level = (entry) => entry.pending || entry.attention ? 2 : entry.unread ? 1 : 0
      return level(a) - level(b) || a.viewed - b.viewed || a.index - b.index
    })
}

export function reorderTabs(entries, move) {
  const order = entries.map((entry) => entry.sessionID)
  rankTabs(entries).forEach((entry, index) => {
    const current = order.indexOf(entry.sessionID)
    if (current === index || move(entry.sessionID, index) === false) return
    order.splice(current, 1)
    order.splice(index, 0, entry.sessionID)
  })
  return order
}
