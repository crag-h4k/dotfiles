import { spawn } from "node:child_process"

// Run the attention shim for a notification group. Outside tmux this does
// nothing on purpose: there is no pane to flag, and OpenCode's own attention.sound
// (configured by the opencode2 wrapper) covers sound there, so playing it here as
// well would double-fire.
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
