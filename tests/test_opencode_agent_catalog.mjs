// tests/test_opencode_agent_catalog.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import {
  agentCategory,
  agentDetails,
  agentOption,
  compareAgents,
  modelLabel,
  summarizeDescription,
} from "../home/dot_config/opencode/v2-plugins/agent-catalog/catalog.mjs"

const CATALOG_TUI_SOURCE = readFileSync(
  new URL("../home/dot_config/opencode/v2-plugins/agent-catalog/tui.tsx", import.meta.url),
  "utf8",
)

const reviewer = {
  id: "reviewer",
  name: "Reviewer",
  mode: "subagent",
  hidden: false,
  model: { providerID: "openai", id: "gpt-5.6", variant: "high" },
  permissions: [],
  description: "Reviews current changes for correctness and security.",
}

test("agent catalog preserves the configured model and role", () => {
  assert.equal(modelLabel(reviewer), "openai/gpt-5.6#high")
  assert.equal(agentCategory(reviewer), "Subagent")
  assert.deepEqual(agentOption(reviewer), {
    title: "Reviewer (reviewer)",
    value: "reviewer",
    description: "subagent · openai/gpt-5.6#high · Reviews current changes for correctness and security.",
    category: "Subagent",
  })
})

test("agent catalog distinguishes hidden and inherited-model agents", () => {
  const hidden = {
    ...reviewer,
    id: "demo",
    name: "demo",
    hidden: true,
    model: undefined,
    permissions: [{ action: "read", resource: "showcase.md", effect: "allow" }],
  }

  assert.equal(modelLabel(hidden), "inherits session model")
  assert.equal(agentCategory(hidden), "Hidden")
  assert.match(agentDetails(hidden), /Visibility: hidden/)
  assert.match(agentDetails(hidden), /Permissions: 1 rules/)
})

test("agent catalog sorts visible primary agents before hidden subagents", () => {
  const primary = { ...reviewer, id: "build", name: "build", mode: "primary", model: undefined }
  const hidden = { ...reviewer, id: "demo", name: "demo", hidden: true }
  assert.deepEqual([hidden, reviewer, primary].sort(compareAgents).map((agent) => agent.id), [
    "build",
    "reviewer",
    "demo",
  ])
})

test("agent catalog compacts multiline descriptions for the selector", () => {
  assert.equal(summarizeDescription("First line.\n\nSecond line."), "First line. Second line.")
  assert.match(summarizeDescription("word ".repeat(40)), /…$/)
})

test("agent catalog uses the subagent-oriented slash commands", () => {
  assert.match(CATALOG_TUI_SOURCE, /slash: \{ name: "subagents", aliases: \["subagents-catalog"\]/)
  assert.doesNotMatch(CATALOG_TUI_SOURCE, /slash: \{ name: "agent-catalog"/)
})
