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
 * apply({ key, args }) runs `command ...args` once per change of key, and the
 * first state is always sent, even "clear": an earlier process in this pane may
 * have left a tint behind, and an elsewhere tint is not cleared by a keypress.
 * release() drops the tint when the TUI goes away. The child is detached with its
 * output ignored and is never awaited: awaiting the old notifier's child is what
 * got it killed.
 */
export function createSink({
  command,
  env = process.env,
  spawn = nodeSpawn,
  isExecutable = executableFile,
  home = homedir(),
} = {}) {
  const path = resolveCommand(command, home)
  // Unknown until the first apply or release, so a leftover tint is never trusted.
  let last

  const available = () => Boolean(env.TMUX && env.TMUX_PANE && path && isExecutable(path))

  function run(args) {
    try {
      const child = spawn(path, args, { detached: true, stdio: "ignore", env })
      child.on?.("error", () => {})
      child.unref?.()
      return true
    } catch {
      return false
    }
  }

  return {
    available,
    apply(state) {
      if (!state || state.key === last || !available()) return false
      if (!run(state.args)) return false
      last = state.key
      return true
    },
    release() {
      if (last === "clear" || !available()) return false
      if (!run(["tint", "clear"])) return false
      last = "clear"
      return true
    },
  }
}
