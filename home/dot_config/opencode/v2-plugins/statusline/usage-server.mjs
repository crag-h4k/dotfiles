import { readFile } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"
import { normalizeUsage, parseClaudeUsage, parseCodexUsage } from "./limits.mjs"

const SOURCES = {
  anthropic: { url: "https://api.anthropic.com/api/oauth/usage", parse: parseClaudeUsage },
  openai: { url: "https://chatgpt.com/backend-api/wham/usage", parse: parseCodexUsage },
}

export async function setupProviderUsage(ctx, rpc) {
  const cache = new Map()
  const pending = new Map()
  const feed = process.env.OPENCODE_PROVIDER_USAGE_FILE
    || join(homedir(), ".cache/opencode/provider-usage/usage.json")

  async function directUsage(id) {
    let connection
    try {
      connection = await ctx.integration.connection.active(id)
    } catch {
      cache.delete(id)
      return undefined
    }
    if (connection?.type !== "credential" || connection.method !== "oauth") {
      cache.delete(id)
      return undefined
    }
    const previous = cache.get(id)
    if (previous?.connection !== connection.id) cache.delete(id)
    const current = cache.get(id)
    const key = `${id}:${connection.id}`
    if (pending.has(key)) return pending.get(key)
    if (current && Date.now() - current.attemptedAt < 60_000) return current.usage
    const state = { connection: connection.id, attemptedAt: Date.now(), usage: current?.usage }
    cache.set(id, state)

    const request = (async () => {
      let usage = current?.usage
      try {
        const credential = await ctx.integration.connection.resolve(connection)
        if (credential?.type !== "oauth" || !credential.access) {
          if (cache.get(id) === state) cache.delete(id)
          return undefined
        }
        const headers = { Authorization: `Bearer ${credential.access}`, Accept: "application/json" }
        if (id === "anthropic") headers["anthropic-beta"] = "oauth-2025-04-20"
        if (id === "openai") {
          const account = credential.metadata?.accountId ?? credential.metadata?.account_id
          if (typeof account === "string" && account) headers["ChatGPT-Account-Id"] = account
        }
        const response = await fetch(SOURCES[id].url, {
          headers,
          redirect: "error",
          signal: AbortSignal.timeout(10_000),
        })
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        const windows = SOURCES[id].parse(await response.json())
        usage = windows.length ? { updatedAt: Date.now(), windows } : undefined
      } catch {
        console.error(`[provider-usage] ${id} quota request failed; retrying after 60 seconds`)
      }
      if (cache.get(id) !== state) return undefined
      state.usage = usage
      state.attemptedAt = Date.now()
      return usage
    })()
    pending.set(key, request)
    try {
      return await request
    } finally {
      pending.delete(key)
    }
  }

  async function gatewayUsage() {
    try {
      const data = JSON.parse(await readFile(feed, "utf8"))
      return Object.fromEntries(Object.entries(data.providers ?? {}).flatMap(([id, usage]) => {
        const normalized = normalizeUsage(usage)
        return normalized ? [[id, normalized]] : []
      }))
    } catch (error) {
      if (error.code !== "ENOENT") console.error("[provider-usage] gateway quota file is unreadable")
      return {}
    }
  }

  return await ctx.rpc.register(rpc, {
    get: async () => {
      const [gateway, anthropic, openai] = await Promise.all([
        gatewayUsage(), directUsage("anthropic"), directUsage("openai"),
      ])
      const providers = { ...gateway }
      for (const [id, usage] of [["anthropic", anthropic], ["openai", openai]]) {
        const normalized = normalizeUsage(usage)
        if (normalized) providers[id] = normalized
      }
      return { providers }
    },
  })
}
