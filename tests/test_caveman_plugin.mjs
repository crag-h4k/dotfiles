// tests/test_caveman_plugin.mjs
import assert from "node:assert/strict"
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"

const source = (await readFile(new URL("../home/dot_config/opencode/plugins/caveman.js", import.meta.url), "utf8"))
  .replace('import { Plugin } from "@opencode/plugin"', "const Plugin = { define: (plugin) => plugin }")
const { configure } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

async function fixture(t, enabled = true, existing) {
  const home = await mkdtemp(join(tmpdir(), "caveman-test-"))
  t.after(() => rm(home, { recursive: true, force: true }))
  const root = join(home, ".caveman/oc2")
  await mkdir(root, { recursive: true })
  await writeFile(join(root, "settings.json"), JSON.stringify({ enabled, provider: "example", url: "http://127.0.0.1:8787" }), { mode: 0o600 })
  await writeFile(join(root, "proxy-token"), "fixture-private-token", { mode: 0o600 })
  const provider = { settings: { baseURL: "https://api.example.com/v1", apiKey: "fixture-key" }, headers: { "x-tenant": "example" }, models: ["preserved"] }
  const agents = ["build", "plan", "auto", "explore", "general", "custom"].map((id) => ({ id, permissions: [{ action: "*", resource: "*", effect: "deny" }] }))
  const tools = [{ id: "caveman_caveman_retrieve" }, { id: "caveman_caveman_compress" }, { id: "other_tool" }]
  let registered = 0
  let hook
  t.mock.method(globalThis, "fetch", async () => new Response("{}"))
  const ctx = {
    session: { async hook(name, callback, scope) { registered++; hook = { name, callback, scope } } },
    mcp: { async list() { return { location: { directory: home }, data: [{ name: "caveman", status: { status: existing?.disabled ? "disabled" : "connected" } }] } } },
    agent: { async transform(fn) { registered++; fn({ list: () => agents, update(id, update) { update(agents.find((a) => a.id === id)) } }) } },
    tool: { async transform(fn) { registered++; fn({ list: () => [...tools], remove(id) { tools.splice(tools.findIndex((t) => t.id === id), 1) } }) } },
  }
  return { home, root, ctx, provider, agents, tools, hook: () => hook, registrations: () => registered }
}

test("disabled routing registers no request hook and does not call the proxy", async (t) => {
  const f = await fixture(t, false)
  await configure(f.ctx, f.home)
  assert.equal(f.registrations(), 0)
  assert.equal(globalThis.fetch.mock.callCount(), 0)
})

test("active routing preserves credentials and permits the whole Caveman tool family", async (t) => {
  const f = await fixture(t)
  await configure(f.ctx, f.home)
  assert.deepEqual(f.hook().scope, { providerID: "example" })
  assert.equal(f.hook().name, "http.request")
  const body = '{"model":"fixture","input":"preserve exact bytes"}'
  const event = { request: new Request("https://api.example.com/v1/responses", {
    method: "POST", body, headers: { Authorization: "Bearer fixture-key", "x-tenant": "example" },
  }) }
  f.hook().callback(event)
  assert.equal(event.request.url, "http://127.0.0.1:8787/compat/example/v1/responses")
  assert.equal(event.request.headers.get("Authorization"), "Bearer fixture-key")
  assert.equal(event.request.headers.get("x-tenant"), "example")
  assert.equal(event.request.headers.get("x-cave-api-key"), "fixture-private-token")
  assert.equal(await event.request.text(), body)
  assert.equal(f.provider.settings.baseURL, "https://api.example.com/v1")
  assert.equal(f.provider.settings.apiKey, "fixture-key")
  assert.deepEqual(f.provider.models, ["preserved"])
  assert.equal(f.provider.headers["x-tenant"], "example")
  assert.deepEqual(f.tools.map((tool) => tool.id), ["caveman_caveman_retrieve", "caveman_caveman_compress", "other_tool"])
})

test("the plugin does not enable an operator-disabled recovery MCP", async (t) => {
  const f = await fixture(t, true, { disabled: true })
  await configure(f.ctx, f.home)
  assert.equal((await f.ctx.mcp.list()).data[0].status.status, "disabled")
  assert.equal(f.hook().name, "http.request")
})

test("tenant prefixes belong to private upstream settings; unsupported routes stay direct", async (t) => {
  const f = await fixture(t)
  await configure(f.ctx, f.home)
  const event = { request: new Request("https://api.example.com/tenant/v1/chat/completions?version=1", { method: "POST", body: "{}" }) }
  f.hook().callback(event)
  assert.equal(event.request.url, "http://127.0.0.1:8787/compat/example/v1/chat/completions?version=1")
  const direct = new Request("https://api.example.com/tenant/v1/responses/compact", { method: "POST", body: "{}" })
  const compact = { request: direct }
  f.hook().callback(compact)
  assert.equal(compact.request, direct)
  assert.equal(compact.request.headers.has("x-cave-api-key"), false)
})

test("public token files are rejected before registration", async (t) => {
  const f = await fixture(t)
  await chmod(join(f.root, "proxy-token"), 0o644)
  await assert.rejects(configure(f.ctx, f.home), /private/)
  assert.equal(f.registrations(), 0)
})

test("failed readiness leaves provider routing untouched", async (t) => {
  const f = await fixture(t)
  t.mock.method(globalThis, "fetch", async () => new Response("", { status: 503 }))
  await assert.rejects(configure(f.ctx, f.home), /not ready/)
  assert.equal(f.registrations(), 0)
  assert.equal(f.provider.settings.baseURL, "https://api.example.com/v1")
})
