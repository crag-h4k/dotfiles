// ~/.config/opencode/plugin/copilot-tiers.ts
// Server-side companion to the statusline model-tier badge (v2-plugins/statusline).
// It classifies the active GitHub Copilot model into GitHub's own picker tier
// (lightweight / versatile / powerful) so the footer can show how heavy a model is.
//
// Premium-request multipliers no longer apply on usage-based / business plans (the API
// says so and returns billing: null), so the picker category is the authoritative
// signal. GitHub's /models endpoint carries it and is reachable with the plain OAuth
// token; no /copilot_internal/v2/token exchange is needed (that endpoint 403s and is
// not required). Credential resolution mirrors the opencode-copilot-statusline package.
//
// Exposes a modelID -> category map over an RPC the TUI statusline reads. Categories
// change rarely, so the result is cached (6h); every failure degrades to the last-good
// map (else empty) and the TUI falls back to a catalog-price band, so a hiccup never
// blanks the badge or disrupts the session.
//
// No UI. Loaded via plugin/ auto-discovery, same as notify.ts.

import { Plugin } from "@opencode/plugin"
import { Rpc } from "@opencode/plugin/rpc"

const INTEGRATION_ID = "github-copilot"
const GITHUB_API = "https://api.github.com"
const COPILOT_API = "https://api.githubcopilot.com"
const FETCH_TIMEOUT_MS = 10_000
const CACHE_TTL_MS = 6 * 60 * 60 * 1_000

// GitHub gates /models behind an editor-shaped request; a generic User-Agent gets a 403
// bot block. These identify us as an editor client (verified working against the live
// endpoint).
const EDITOR_HEADERS: Record<string, string> = {
  Accept: "application/json",
  "Copilot-Integration-Id": "vscode-chat",
  "Editor-Version": "vscode/1.95.0",
  "User-Agent": "GitHubCopilotChat/0.22.0",
}

type CategoryMap = Record<string, string>

const TiersRpc = Rpc.define({
  id: "dotfiles.copilot-tiers",
  methods: {
    get: {
      input: { type: "object", properties: {}, additionalProperties: false },
      output: {
        type: "object",
        properties: {
          models: { type: "object", additionalProperties: { type: "string" } },
        },
        additionalProperties: false,
      },
    },
  },
  events: {},
})

// Honor a GitHub Enterprise base the same way copilot-statusline's apiBase does.
function githubBase(credential: any): string {
  const enterprise = credential?.metadata?.enterpriseUrl
  if (typeof enterprise === "string" && enterprise) {
    return `https://api.${enterprise.replace(/\/+$/, "")}`
  }
  return GITHUB_API
}

export default Plugin.define({
  id: "dotfiles.copilot-tiers",
  async setup(ctx) {
    let cache: CategoryMap = {}
    let fetchedAt = 0

    async function resolveToken(): Promise<{ token: string; base: string } | undefined> {
      const connection = await ctx.integration.connection.active(INTEGRATION_ID)
      if (!connection) return
      const credential = await ctx.integration.connection.resolve(connection)
      if (credential?.type !== "oauth" && credential?.type !== "key") return
      const token =
        credential.type === "oauth" ? credential.access || credential.refresh : credential.key
      if (!token) return
      return { token, base: githubBase(credential) }
    }

    // The /models host is account-specific (e.g. api.business.githubcopilot.com for
    // business plans); read it from /copilot_internal/user rather than assuming.
    async function copilotApiBase(auth: { token: string; base: string }): Promise<string> {
      try {
        const res = await fetch(`${auth.base}/copilot_internal/user`, {
          headers: { ...EDITOR_HEADERS, Authorization: `Bearer ${auth.token}` },
          signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
        })
        if (res.ok) {
          const body = (await res.json()) as { endpoints?: { api?: string } }
          if (body.endpoints?.api) return body.endpoints.api
        }
      } catch {
        // fall through to the default host
      }
      return COPILOT_API
    }

    async function fetchCategories(): Promise<CategoryMap | undefined> {
      const auth = await resolveToken()
      if (!auth) return
      const api = await copilotApiBase(auth)
      const res = await fetch(`${api}/models`, {
        headers: { ...EDITOR_HEADERS, Authorization: `Bearer ${auth.token}` },
        signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      })
      if (!res.ok) return
      const body = (await res.json()) as {
        data?: Array<{ id?: string; model_picker_category?: string }>
      }
      if (!Array.isArray(body.data)) return
      const map: CategoryMap = {}
      for (const model of body.data) {
        if (model.id && typeof model.model_picker_category === "string") {
          map[model.id] = model.model_picker_category
        }
      }
      return map
    }

    async function categories(): Promise<CategoryMap> {
      const now = Date.now()
      if (now - fetchedAt < CACHE_TTL_MS && Object.keys(cache).length > 0) return cache
      try {
        const fresh = await fetchCategories()
        if (fresh && Object.keys(fresh).length > 0) {
          cache = fresh
          fetchedAt = now
          console.error(`[copilot-tiers] loaded ${Object.keys(fresh).length} model categories`)
        } else {
          console.error("[copilot-tiers] no categories resolved; using last-good/fallback")
        }
      } catch (err) {
        console.error("[copilot-tiers] category fetch failed; using last-good/fallback:", err)
      }
      return cache
    }

    await ctx.rpc.register(TiersRpc, {
      get: async () => ({ models: await categories() }),
    })
  },
})
