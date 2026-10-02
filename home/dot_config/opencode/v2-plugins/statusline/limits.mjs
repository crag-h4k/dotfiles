export const LIMIT_MAX_AGE_MS = 5 * 60_000
export const LIMIT_ICON = "󰓅"

export const LIMITS_RPC_SCHEMA = {
  id: "dotfiles.provider-usage",
  methods: {
    get: {
      input: { type: "object", properties: {}, additionalProperties: false },
      output: {
        type: "object",
        properties: {
          providers: {
            type: "object",
            additionalProperties: {
              type: "object",
              properties: {
                updatedAt: { type: "number" },
                windows: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      period: { type: "string", enum: ["5h", "week"] },
                      usedPercent: { type: "number", minimum: 0, maximum: 100 },
                    },
                    required: ["period", "usedPercent"],
                    additionalProperties: false,
                  },
                },
              },
              required: ["updatedAt", "windows"],
              additionalProperties: false,
            },
          },
        },
        required: ["providers"],
        additionalProperties: false,
      },
    },
  },
  events: {},
}

function window(period, percent) {
  if (typeof percent !== "number" || !Number.isFinite(percent)) return undefined
  return { period, usedPercent: Math.min(100, Math.max(0, Math.round(percent))) }
}

export function parseCodexUsage(body) {
  const windows = []
  for (const key of ["primary_window", "secondary_window"]) {
    const value = body?.rate_limit?.[key]
    const period = value?.limit_window_seconds === 604_800
      ? "week"
      : value?.limit_window_seconds === 18_000 ? "5h" : undefined
    const parsed = period && window(period, value.used_percent)
    if (parsed && !windows.some((item) => item.period === period)) windows.push(parsed)
  }
  return windows.sort((a, b) => (a.period === "5h" ? 0 : 1) - (b.period === "5h" ? 0 : 1))
}

export function parseClaudeUsage(body) {
  return [window("5h", body?.five_hour?.utilization), window("week", body?.seven_day?.utilization)]
    .filter(Boolean)
}

export function normalizeUsage(usage, now = Date.now()) {
  if (!usage || typeof usage.updatedAt !== "number" || !Number.isFinite(usage.updatedAt)) return undefined
  const age = now - usage.updatedAt
  if (age < 0 || age >= LIMIT_MAX_AGE_MS || !Array.isArray(usage.windows)) return undefined
  const windows = ["5h", "week"].flatMap((period) => {
    const value = usage.windows.find((item) => item?.period === period)
    const parsed = window(period, value?.usedPercent)
    return parsed ? [parsed] : []
  })
  if (!windows.length) return undefined
  return { updatedAt: usage.updatedAt, windows }
}

export function limitSummary(usage, now = Date.now()) {
  const normalized = normalizeUsage(usage, now)
  if (!normalized) return undefined
  const { windows } = normalized
  return {
    text: windows.map((value) => `${value.period} ${value.usedPercent}%`).join(" · "),
    usedPercent: Math.max(...windows.map((value) => value.usedPercent)),
  }
}
