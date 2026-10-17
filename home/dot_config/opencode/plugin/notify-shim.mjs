import { spawn } from "node:child_process"

export function fire(group) {
  if (!process.env.TMUX || !process.env.TMUX_PANE) return
  try {
    const shim = `${process.env.HOME ?? ""}/.config/notify/opencode-events.sh`
    // Execution teardown must not reap the notifier before it reaches tmux.
    const child = spawn("bash", [shim, "fire", group], { detached: true, stdio: "ignore" })
    child.on("error", () => {})
    child.unref()
  } catch {
    /* notifier is best-effort */
  }
}
