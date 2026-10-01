export function weeklyQuota(response) {
  const rateLimit = response?.rate_limit
  if (!rateLimit || typeof rateLimit !== "object") return

  const windows = [rateLimit.primary_window, rateLimit.secondary_window].filter(
    (window) => window?.limit_window_seconds === 604_800,
  )
  if (windows.length !== 1) return
  const used = windows[0].used_percent
  if (typeof used !== "number" || !Number.isFinite(used) || used < 0 || used > 100) return
  return { remainingPercent: Math.round(100 - used) }
}

export function quotaLabel(providerID, copilot, openai) {
  if (providerID === "github-copilot") {
    if (!copilot) return { text: "GitHub Copilot", usedPercent: 100 }
    if (copilot.unlimited) return { text: "GitHub Copilot ∞", usedPercent: 0 }
    return { text: `GitHub Copilot ${copilot.usedPercent}%`, usedPercent: copilot.usedPercent }
  }
  if (providerID !== "openai" || openai?.auth !== "oauth") return
  if (!openai.weekly) return { text: "Codex unavailable", usedPercent: 100 }
  return {
    text: `Codex ${openai.weekly.remainingPercent}% left`,
    usedPercent: 100 - openai.weekly.remainingPercent,
  }
}
