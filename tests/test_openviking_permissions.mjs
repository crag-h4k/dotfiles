// tests/test_openviking_permissions.mjs
import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const path = new URL("../home/dot_config/opencode/plugins/openviking-permissions.js", import.meta.url)
const source = (await readFile(path, "utf8")).replace(
  'import { Plugin } from "@opencode/plugin"',
  "const Plugin = { define: (plugin) => plugin }",
)
const { default: plugin } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`)

async function apply(agents) {
  await plugin.setup({
    agent: {
      async transform(callback) {
        callback({
          list: () => agents,
          update(id, update) { update(agents.find((agent) => agent.id === id)) },
        })
      },
    },
  })
}

function effect(rules, action, resource) {
  let result = "ask"
  const matches = (pattern, value) => new RegExp(`^${pattern.replace(/[.+^${}()\[\]\\]/g, "\\$&").replaceAll("*", ".*").replaceAll("?", ".")}$`).test(value)
  for (const rule of rules) {
    if (matches(rule.action, action) && matches(rule.resource, resource)) result = rule.effect
  }
  return result
}

test("OpenViking tools and skills remain available in every agent mode", async () => {
  const agents = ["build", "plan", "auto", "explore", "general", "custom-reviewer"].map((id) => ({
    id,
    permissions: [{ action: "*", resource: "*", effect: "deny" }],
  }))
  await apply(agents)
  for (const agent of agents) {
    for (const tool of ["openviking_find", "openviking_read", "openviking_write", "openviking_forget"]) {
      assert.equal(effect(agent.permissions, tool, "*"), "allow")
    }
    for (const skill of ["openviking-memory", "openviking-skills", "ov-experience-memory"]) {
      assert.equal(effect(agent.permissions, "skill", skill), "allow")
    }
    assert.equal(effect(agent.permissions, "edit", "secrets.env"), "deny")
    assert.equal(effect(agent.permissions, "shell", "git push origin main"), "deny")
    assert.equal(effect(agent.permissions, "skill", "unrelated-skill"), "deny")
  }
})

test("Existing rules survive and repeated transforms do not accumulate allows", async () => {
  const original = [{ action: "shell", resource: "git push *", effect: "ask" }]
  const agents = [{ id: "custom", permissions: structuredClone(original) }]
  await apply(agents)
  const once = structuredClone(agents)
  await apply(agents)
  assert.deepEqual(agents, once)
  assert.deepEqual(agents[0].permissions.slice(0, original.length), original)
  assert.equal(effect(agents[0].permissions, "shell", "git push origin main"), "ask")
})

test("Agents with no explicit rules receive only the OpenViking exceptions", async () => {
  const agents = [{ id: "future-agent" }]
  await apply(agents)
  assert.equal(agents[0].permissions.length, 3)
  assert.equal(effect(agents[0].permissions, "openviking_search", "*"), "allow")
  assert.equal(effect(agents[0].permissions, "shell", "openvikingctl stop"), "ask")
})
