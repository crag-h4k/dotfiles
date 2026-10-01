// tests/test_opencode_statusline.mjs
import assert from "node:assert/strict"
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import {
  LIMIT_MAX_AGE_MS, LIMITS_RPC_SCHEMA, limitSummary, parseClaudeUsage, parseCodexUsage,
} from "../home/dot_config/opencode/v2-plugins/statusline/limits.mjs"
import { setupProviderUsage } from "../home/dot_config/opencode/v2-plugins/statusline/usage-server.mjs"

import {
  BACKGROUND_SPINNER_FRAMES,
  CONTEXT_ICON,
  COST_ICON,
  FOREGROUND_SPINNER_FRAMES,
  PROVIDER_ICON,
  SUBAGENT_QUEUED_ICON,
  familyActivity,
  foregroundSpinnerActive,
  foregroundSpinnerFrame,
  spinnerClockActive,
  statusVisibility,
  subagentIcon,
  subagentLabel,
  waitingForInput,
} from "../home/dot_config/opencode/v2-plugins/statusline/spinner.mjs"

const STATUSLINE_SOURCE = readFileSync(
  new URL("../home/dot_config/opencode/v2-plugins/statusline/tui.tsx.tmpl", import.meta.url),
  "utf8",
)

test("spinner frames are distinct single-cell glyphs", () => {
  for (const frame of [...FOREGROUND_SPINNER_FRAMES, ...BACKGROUND_SPINNER_FRAMES]) {
    assert.equal([...frame].length, 1)
  }
  assert.equal(new Set(FOREGROUND_SPINNER_FRAMES).size, FOREGROUND_SPINNER_FRAMES.length)
  assert.equal(new Set(BACKGROUND_SPINNER_FRAMES).size, 3)
  assert.equal(
    FOREGROUND_SPINNER_FRAMES.some((frame) => BACKGROUND_SPINNER_FRAMES.includes(frame)),
    false,
  )
  for (const icon of [CONTEXT_ICON, COST_ICON, PROVIDER_ICON]) {
    assert.equal([...icon].length, 1)
  }
})

test("foreground spinner follows execution, input, shell, and visibility state", () => {
  const running = {
    mode: "normal",
    status: "running",
    waiting: false,
    identityVisible: true,
  }

  assert.equal(foregroundSpinnerActive(running), true)
  assert.equal(foregroundSpinnerActive({ ...running, status: "idle" }), false)
  assert.equal(foregroundSpinnerActive({ ...running, waiting: true }), false)
  assert.equal(foregroundSpinnerActive({ ...running, mode: "shell" }), false)
  assert.equal(foregroundSpinnerActive({ ...running, identityVisible: false }), false)
  assert.equal(waitingForInput(0, 0), false)
  assert.equal(waitingForInput(1, 0), true)
  assert.equal(waitingForInput(0, 1), true)
})

test("subagent activity keeps running and queued counts", () => {
  const statuses = new Map([
    ["child-a", "running"],
    ["child-b", "idle"],
    ["child-c", "running"],
  ])
  const pending = new Map([
    ["child-a", 1],
    ["child-b", 2],
    ["child-c", 0],
  ])
  const activity = familyActivity(
    [...statuses.keys()],
    (sessionID) => statuses.get(sessionID),
    (sessionID) => pending.get(sessionID),
  )

  assert.deepEqual(activity, { running: 2, queued: 3 })
  assert.equal(subagentLabel(activity), "2 run · 3 queued")
  assert.equal(subagentLabel({ running: 0, queued: 3 }), "3 queued")
})

test("running subagents animate while queued-only work stays static", () => {
  assert.equal(subagentIcon(0, 0), SUBAGENT_QUEUED_ICON)
  assert.equal(subagentIcon(0, 3), SUBAGENT_QUEUED_ICON)
  assert.equal(subagentIcon(1, 0), BACKGROUND_SPINNER_FRAMES[0])
  assert.equal(subagentIcon(1, 2), BACKGROUND_SPINNER_FRAMES[2])
  assert.equal(foregroundSpinnerFrame(10), FOREGROUND_SPINNER_FRAMES[0])
  assert.equal(spinnerClockActive(false, 0), false)
  assert.equal(spinnerClockActive(true, 0), true)
  assert.equal(spinnerClockActive(false, 1), true)
  assert.equal(spinnerClockActive(true, 1), true)
})

test("responsive thresholds hold at narrow, 99, 200, and 240 columns", () => {
  assert.deepEqual(statusVisibility(60, true, false), {
    identity: false,
    elapsed: false,
    context: false,
    cost: false,
    provider: false,
  })
  assert.deepEqual(statusVisibility(99, true, false), {
    identity: false,
    elapsed: false,
    context: true,
    cost: false,
    provider: false,
  })
  assert.deepEqual(statusVisibility(99, false, false), {
    identity: true,
    elapsed: false,
    context: true,
    cost: false,
    provider: false,
  })
  assert.deepEqual(statusVisibility(200, true, false), {
    identity: true,
    elapsed: true,
    context: true,
    cost: true,
    provider: true,
  })
  assert.deepEqual(statusVisibility(240, true, false), {
    identity: true,
    elapsed: true,
    context: true,
    cost: true,
    provider: true,
  })
  assert.deepEqual(statusVisibility(240, false, true), {
    identity: false,
    elapsed: false,
    context: false,
    cost: false,
    provider: false,
  })
})

test("usage and provider values render as left-side pills", () => {
  assert.match(STATUSLINE_SOURCE, /icon=\{CONTEXT_ICON\}/)
  assert.match(STATUSLINE_SOURCE, /icon=\{COST_ICON\}/)
  assert.match(STATUSLINE_SOURCE, /icon=\{value\(\)\.icon \?\? PROVIDER_ICON\}/)
  assert.doesNotMatch(STATUSLINE_SOURCE, /metrics\(\)\.join/)
  assert.doesNotMatch(STATUSLINE_SOURCE, /<box flexGrow=\{1\} \/>/)
  assert.match(STATUSLINE_SOURCE, /contextUsage=\{usage\(\)\.context\}/)
  assert.match(STATUSLINE_SOURCE, /provider=\{provider\(\)\}/)
})

test("Codex classifies quota windows by duration, including weekly-only primary windows", () => {
  assert.deepEqual(parseCodexUsage({ rate_limit: {
    primary_window: { limit_window_seconds: 604800, used_percent: 92 },
    secondary_window: null,
  } }), [{ period: "week", usedPercent: 92 }])
  assert.deepEqual(parseCodexUsage({ rate_limit: {
    primary_window: { limit_window_seconds: 604800, used_percent: 35.4 },
    secondary_window: { limit_window_seconds: 18000, used_percent: 0 },
  } }), [{ period: "5h", usedPercent: 0 }, { period: "week", usedPercent: 35 }])
  for (const body of [null, {}, { rate_limit: { primary_window: {} } }]) {
    assert.deepEqual(parseCodexUsage(body), [])
  }
  assert.deepEqual(parseCodexUsage({ rate_limit: {
    primary_window: { limit_window_seconds: 604800, used_percent: "32" },
    secondary_window: { limit_window_seconds: 3600, used_percent: 12 },
  } }), [])
})

test("Claude hides absent limits while preserving zero usage", () => {
  assert.deepEqual(parseClaudeUsage({ five_hour: { utilization: 0 }, seven_day: { utilization: 40.8 } }), [
    { period: "5h", usedPercent: 0 }, { period: "week", usedPercent: 41 },
  ])
  assert.deepEqual(parseClaudeUsage({ five_hour: null, seven_day: { utilization: 99 } }), [
    { period: "week", usedPercent: 99 },
  ])
  assert.deepEqual(parseClaudeUsage({ seven_day: { utilization: null } }), [])
  assert.deepEqual(parseClaudeUsage({ seven_day: { utilization: Infinity } }), [])
})

test("quota labels show actual windows and expire during outages", () => {
  const usage = { updatedAt: 1000, windows: [{ period: "week", usedPercent: 92 }] }
  assert.deepEqual(limitSummary(usage, 1000), { text: "week 92%", usedPercent: 92 })
  assert.equal(limitSummary(usage, 1000 + LIMIT_MAX_AGE_MS), undefined)
  assert.equal(limitSummary(usage, 999), undefined)
  assert.equal(limitSummary({ ...usage, windows: [] }, 1000), undefined)
  assert.deepEqual(limitSummary({ ...usage, windows: [
    { period: "week", usedPercent: 32 }, { period: "5h", usedPercent: 99 },
  ] }, 1000), { text: "5h 99% · week 32%", usedPercent: 99 })
})

async function quotaRpc(t, connections = {}) {
  const directory = mkdtempSync(join(tmpdir(), "opencode-quota-"))
  const feed = join(directory, "usage.json")
  const before = process.env.OPENCODE_PROVIDER_USAGE_FILE
  process.env.OPENCODE_PROVIDER_USAGE_FILE = feed
  t.after(() => {
    if (before === undefined) delete process.env.OPENCODE_PROVIDER_USAGE_FILE
    else process.env.OPENCODE_PROVIDER_USAGE_FILE = before
    rmSync(directory, { recursive: true, force: true })
  })
  let handlers
  const ctx = {
    integration: { connection: {
      active: async (id) => connections[id],
      resolve: async () => ({ type: "oauth", access: "test-access", metadata: { accountId: "test-account" } }),
    } },
    rpc: { register: async (definition, methods) => {
      assert.equal(definition, LIMITS_RPC_SCHEMA)
      handlers = methods
      return { dispose: async () => {} }
    } },
  }
  await setupProviderUsage(ctx, LIMITS_RPC_SCHEMA)
  return { feed, ctx, get: () => handlers.get({}) }
}

test("server combines gateway and direct limits without returning credentials", async (t) => {
  const { feed, get } = await quotaRpc(t, {
    openai: { type: "credential", method: "oauth", id: "account-a" },
    anthropic: { type: "credential", method: "oauth", id: "account-b" },
  })
  writeFileSync(feed, JSON.stringify({ providers: { household: {
    updatedAt: Date.now(), windows: [{ period: "week", usedPercent: 92, token: "excluded" }],
    access_token: "excluded",
  } } }))
  const calls = []
  t.mock.method(globalThis, "fetch", async (url, options) => {
    calls.push({ url, options })
    return { ok: true, json: async () => url.includes("anthropic")
      ? { seven_day: { utilization: 28 } }
      : { rate_limit: { primary_window: { limit_window_seconds: 604800, used_percent: 44 } } } }
  })
  const result = await get()
  assert.deepEqual(Object.keys(result.providers).sort(), ["anthropic", "household", "openai"])
  assert.equal(result.providers.household.windows[0].usedPercent, 92)
  assert.equal(result.providers.openai.windows[0].usedPercent, 44)
  assert.doesNotMatch(JSON.stringify(result), /excluded|test-access|test-account|access_token/)
  assert.equal(calls.find((call) => call.url.includes("chatgpt")).options.headers["ChatGPT-Account-Id"], "test-account")
  assert.equal(calls.find((call) => call.url.includes("anthropic")).options.headers["anthropic-beta"], "oauth-2025-04-20")
  assert.ok(calls.every((call) => call.options.redirect === "error"))
  await get()
  assert.equal(calls.length, 2, "shared RPC cache prevents extra requests within a minute")
})

test("API keys have no subscription quota, and expired gateway figures disappear", async (t) => {
  const { feed, get } = await quotaRpc(t, { openai: { type: "credential", method: "key", id: "key-a" } })
  writeFileSync(feed, JSON.stringify({ providers: { household: {
    updatedAt: Date.now() - LIMIT_MAX_AGE_MS, windows: [{ period: "week", usedPercent: 92 }],
  } } }))
  t.mock.method(globalThis, "fetch", async () => assert.fail("API keys must not call OAuth quota endpoints"))
  assert.deepEqual(await get(), { providers: {} })
  writeFileSync(feed, "invalid JSON")
  t.mock.method(console, "error", () => {})
  assert.deepEqual(await get(), { providers: {} })
})

test("direct quota failures retain figures briefly, and account changes clear them", async (t) => {
  let now = 1000
  t.mock.method(Date, "now", () => now)
  t.mock.method(console, "error", () => {})
  const connections = { openai: { type: "credential", method: "oauth", id: "account-a" } }
  const { get } = await quotaRpc(t, connections)
  let ok = true
  t.mock.method(globalThis, "fetch", async () => ({ ok, status: 503, json: async () => ({
    rate_limit: { primary_window: { limit_window_seconds: 604800, used_percent: 92 } },
  }) }))
  assert.equal((await get()).providers.openai.windows[0].usedPercent, 92)
  now += 60000
  ok = false
  assert.equal((await get()).providers.openai.updatedAt, 1000)
  connections.openai.id = "account-b"
  assert.deepEqual(await get(), { providers: {} }, "switching accounts must not reuse the previous quota")
  connections.openai.id = "account-c"
  ok = true
  assert.equal((await get()).providers.openai.updatedAt, now)
  ok = false
  now += LIMIT_MAX_AGE_MS
  assert.deepEqual(await get(), { providers: {} })
})
