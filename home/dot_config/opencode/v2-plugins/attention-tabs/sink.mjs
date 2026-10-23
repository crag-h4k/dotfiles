// ~/.config/opencode/v2-plugins/attention-tabs/sink.mjs
// The optional tmux sink. It asks the dotfiles notifier to tint this pane, and
// is a silent no-op anywhere the notifier or tmux is missing, so the rest of
// attention-tabs works unchanged.
import { spawn as nodeSpawn } from "node:child_process"
import { accessSync, constants, statSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

export function resolveCommand(command, home) {
  if (typeof command !== "string" || command.trim() === "") return undefined
  if (command === "~") return home
  return command.startsWith("~/") ? join(home, command.slice(2)) : command
}

function executableFile(path) {
  try {
    if (!statSync(path).isFile()) return false
    accessSync(path, constants.X_OK)
    return true
  } catch {
    return false
  }
}

/**
 * command: notifier path, a leading ~ expands. env must hold TMUX and TMUX_PANE.
 * apply({ key, args }) runs `command ...args` once per change of key. The child
 * is detached with its output ignored and is never awaited: awaiting the old
 * notifier's child is what got it killed.
 */
export function createSink({
  command,
  env = process.env,
  spawn = nodeSpawn,
  isExecutable = executableFile,
  home = homedir(),
} = {}) {
  const path = resolveCommand(command, home)
  // Nothing pending at start means nothing to clear.
  let last = "clear"

  const available = () => Boolean(env.TMUX && env.TMUX_PANE && path && isExecutable(path))

  return {
    available,
    apply(state) {
      if (!state || state.key === last || !available()) return false
      try {
        const child = spawn(path, state.args, { detached: true, stdio: "ignore", env })
        child.on?.("error", () => {})
        child.unref?.()
      } catch {
        return false
      }
      last = state.key
      return true
    },
  }
}
