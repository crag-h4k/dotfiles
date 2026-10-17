// tests/test_opencode_demo.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import { demoModel, runDemo } from "../home/dot_config/opencode/v2-plugins/demo/demo.mjs"

const DEMO_TUI_SOURCE = readFileSync(
  new URL("../home/dot_config/opencode/v2-plugins/demo/tui.tsx", import.meta.url),
  "utf8",
)

function setup() {
  const calls = []
  const context = {
    client: {
      agent: { list: async () => ({ data: [{ id: "dotfiles-demo" }] }) },
      session: {
        create: async (value) => { calls.push(["create", value]); return { id: "demo-session" } },
        prompt: async (value) => { calls.push(["prompt", value]) },
        wait: async (value) => { calls.push(["wait", value]) },
        get: async () => ({ outcome: "succeeded", tokens: { input: 400, output: 50, reasoning: 0 } }),
      },
    },
    ui: {
      model: { current: () => ({ providerID: "household", modelID: "example", variant: "high" }), variant: { list: () => ["high", "low"] } },
      tabs: { open: (id) => { calls.push(["tab", id]) } },
      router: { navigate: (route) => { calls.push(["route", route]) } },
      toast: { show: (value) => { calls.push(["toast", value]) } },
    },
  }
  return { context, calls }
}

test("demo keeps the selected provider and chooses the lowest supported reasoning", () => {
  const current = { providerID: "private", modelID: "my-model", variant: "xhigh" }
  assert.deepEqual(demoModel(current, ["high", "minimal", "low"]), { providerID: "private", id: "my-model", variant: "minimal" })
  assert.deepEqual(demoModel(current, []), { providerID: "private", id: "my-model" })
})

test("arguments, including the retired diagnostics view, never create a session or prompt a model", async () => {
  for (const argument of ["diagnostics", "/demo diagnostics", "anything else"]) {
    const { context, calls } = setup()
    await runDemo(context, argument, "/fixture")
    assert.equal(calls.length, 1)
    assert.equal(calls[0][0], "toast")
    assert.equal(calls[0][1].variant, "warning")
  }
})

test("a bare /demo still starts the live task", async () => {
  for (const argument of [undefined, "", "/demo", "demo "]) {
    const { context, calls } = setup()
    await runDemo(context, argument, "/fixture")
    assert.equal(calls.filter(([kind]) => kind === "create").length, 1)
  }
})

test("the demo is its own plugin with the /demo slash command", () => {
  assert.match(DEMO_TUI_SOURCE, /id: "dotfiles\.demo"/)
  assert.match(DEMO_TUI_SOURCE, /slash: \{ name: "demo", arguments: true \}/)
  assert.doesNotMatch(DEMO_TUI_SOURCE, /diagnostics/i)
})

test("live demo starts fresh, restricts reads, prompts once and reports actual usage", async () => {
  const { context, calls } = setup()
  await runDemo(context, "", "/fixture")
  const create = calls.find(([kind]) => kind === "create")[1]
  assert.equal(create.parentID, undefined)
  assert.equal(create.agent, "dotfiles-demo")
  assert.deepEqual(create.location, { directory: "/fixture" })
  assert.deepEqual(create.permissions, [
    { action: "*", resource: "*", effect: "deny" },
    { action: "read", resource: "showcase.md", effect: "allow" },
    { action: "read", resource: "/fixture/showcase.md", effect: "allow" },
    { action: "caveman_*", resource: "*", effect: "allow" },
  ])
  assert.equal(calls.filter(([kind]) => kind === "prompt").length, 1)
  assert.match(calls.at(-1)[1].message, /400 input · 50 output · 0 reasoning/)
})

test("missing server agent and failed prompts do not retry", async () => {
  const missing = setup()
  missing.context.client.agent.list = async () => ({ data: [] })
  await assert.rejects(runDemo(missing.context, "", "/fixture"), /no dotfiles-demo agent/)
  assert.deepEqual(missing.calls, [])
  const failed = setup()
  let attempts = 0
  failed.context.client.session.prompt = async () => { attempts++; throw new Error("offline") }
  await assert.rejects(runDemo(failed.context, "", "/fixture"), /offline/)
  assert.equal(attempts, 1)
})
