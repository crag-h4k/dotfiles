// tests/test_opencode_statusline.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

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
  assert.match(STATUSLINE_SOURCE, /icon=\{PROVIDER_ICON\}/)
  assert.doesNotMatch(STATUSLINE_SOURCE, /metrics\(\)\.join/)
  assert.doesNotMatch(STATUSLINE_SOURCE, /<box flexGrow=\{1\} \/>/)
  assert.match(STATUSLINE_SOURCE, /contextUsage=\{usage\(\)\.context\}/)
  assert.match(STATUSLINE_SOURCE, /provider=\{provider\(\)\}/)
})
