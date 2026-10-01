import { Plugin } from "@opencode/plugin"
import { Rpc } from "@opencode/plugin/rpc"
import { weeklyQuota } from "../v2-plugins/statusline/openai-quota.mjs"

const USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
const CACHE_MS = 60_000

const QuotaRpc = Rpc.define({
  id: "dotfiles.codex-quota",
  methods: {
    get: {
      input: { type: "object", properties: {}, additionalProperties: false },
      output: {
        type: "object",
        properties: {
          auth: { type: "string", enum: ["oauth", "key", "none"] },
          weekly: {
            type: "object",
            properties: { remainingPercent: { type: "number" } },
            required: ["remainingPercent"],
            additionalProperties: false,
          },
        },
        required: ["auth"],
        additionalProperties: false,
      },
    },
  },
  events: {},
})

export default Plugin.define({
  id: "dotfiles.codex-quota",
  async setup(ctx) {
    let cached: { remainingPercent: number } | undefined
    let identity: string | undefined
    let fetchedAt = 0

    const registration = await ctx.rpc.register(QuotaRpc, {
      get: async () => {
        const connection = await ctx.integration.connection.active("openai")
        if (!connection) return { auth: "none" }
        const credential = await ctx.integration.connection.resolve(connection)
        if (credential?.type !== "oauth") {
          return { auth: credential ? "key" : "none" }
        }

        const access = credential.access
        if (typeof access !== "string" || !access || credential.expires <= Date.now()) {
          return { auth: "oauth" }
        }
        if (access !== identity) {
          identity = access
          cached = undefined
          fetchedAt = 0
        }
        if (Date.now() - fetchedAt < CACHE_MS) return { auth: "oauth", weekly: cached }

        try {
          const headers: Record<string, string> = { Authorization: `Bearer ${access}` }
          const account = credential.metadata?.accountId ?? credential.metadata?.account_id
          if (typeof account === "string" && account) headers["ChatGPT-Account-Id"] = account
          const response = await fetch(USAGE_URL, {
            headers,
            redirect: "error",
            signal: AbortSignal.timeout(10_000),
          })
          if (!response.ok) return { auth: "oauth" }
          const weekly = weeklyQuota(await response.json())
          cached = weekly
          fetchedAt = Date.now()
          return { auth: "oauth", weekly }
        } catch {
          return { auth: "oauth" }
        }
      },
    })
    return () => registration.dispose()
  },
})
