// ~/.config/opencode/v2-plugins/statusline/spinner.mjs
// Pure statusline animation and layout helpers.

export const SPINNER_INTERVAL_MS = 80
export const FOREGROUND_SPINNER_FRAMES = Object.freeze([
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
])
export const BACKGROUND_SPINNER_FRAMES = Object.freeze([".", "o", "O", "o"])
export const SUBAGENT_QUEUED_ICON = "󰓻"
export const CONTEXT_ICON = "󰍛"
export const COST_ICON = "≈"
export const PROVIDER_ICON = "󰊤"

/**
 * @param {readonly string[]} frames
 * @param {number} tick
 */
function spinnerFrame(frames, tick) {
  return frames[tick % frames.length]
}

/** @param {number} tick */
export function foregroundSpinnerFrame(tick) {
  return spinnerFrame(FOREGROUND_SPINNER_FRAMES, tick)
}

/**
 * @param {number} running
 * @param {number} tick
 */
export function subagentIcon(running, tick) {
  return running > 0 ? spinnerFrame(BACKGROUND_SPINNER_FRAMES, tick) : SUBAGENT_QUEUED_ICON
}

/**
 * @param {number} permissions
 * @param {number} forms
 */
export function waitingForInput(permissions, forms) {
  return permissions > 0 || forms > 0
}

/**
 * @param {{
 *   mode: "normal" | "shell"
 *   status: "idle" | "running"
 *   waiting: boolean
 *   identityVisible: boolean
 * }} state
 */
export function foregroundSpinnerActive(state) {
  return (
    state.identityVisible &&
    state.mode === "normal" &&
    state.status === "running" &&
    !state.waiting
  )
}

/**
 * @param {boolean} foreground
 * @param {number} runningChildren
 */
export function spinnerClockActive(foreground, runningChildren) {
  return foreground || runningChildren > 0
}

/**
 * @param {string[]} children
 * @param {(sessionID: string) => "idle" | "running"} status
 * @param {(sessionID: string) => number} pending
 */
export function familyActivity(children, status, pending) {
  return children.reduce(
    (activity, child) => ({
      running: activity.running + (status(child) === "running" ? 1 : 0),
      queued: activity.queued + pending(child),
    }),
    { running: 0, queued: 0 },
  )
}

/** @param {{ running: number; queued: number }} activity */
export function subagentLabel(activity) {
  return [
    activity.running ? `${activity.running} run` : "",
    activity.queued ? `${activity.queued} queued` : "",
  ]
    .filter(Boolean)
    .join(" · ")
}

/**
 * @param {number} width
 * @param {boolean} hasGit
 * @param {boolean} home
 */
export function statusVisibility(width, hasGit, home) {
  return {
    identity: !home && width >= 85 && (!hasGit || width >= 125),
    elapsed: !home && width >= 115 && (!hasGit || width >= 150),
    context: !home && width >= (hasGit ? 95 : 75),
    cost: !home && width >= (hasGit ? 135 : 105),
    provider: !home && width >= (hasGit ? 175 : 145),
  }
}
