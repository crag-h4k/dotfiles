export async function notificationGroup(event, { getSession }) {
  if (event.type === "form.created") return "opencode_question"
  const sessionID = event.data?.sessionID
  if (!sessionID) return

  if (event.type === "session.execution.succeeded") {
    const session = await getSession({ sessionID })
    return session.parentID ? undefined : "opencode"
  }
  if (event.type !== "permission.asked") return

  const session = await getSession({ sessionID })
  // Auto's TUI handler owns notification after an approval failure.
  if (session.agent === "auto" && event.data.action !== "question") return
  return "opencode_permission"
}
