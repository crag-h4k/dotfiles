export function nextMode(agent) {
  if (agent === "build") return "plan"
  if (agent === "plan") return "auto"
  return "build"
}

export function shouldAutoApprove({ agent, action }) {
  return agent === "auto" && action !== "question"
}
