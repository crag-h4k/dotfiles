---
description: A small read-only demonstration of this OpenCode setup
mode: primary
hidden: true
steps: 2
permissions:
  - action: "*"
    resource: "*"
    effect: deny
  - action: read
    resource: "showcase.md"
    effect: allow
  - action: read
    resource: "~/.config/opencode/demo/showcase.md"
    effect: allow
  - action: "openviking_*"
    resource: "*"
    effect: allow
  - action: skill
    resource: "openviking-*"
    effect: allow
  - action: skill
    resource: ov-experience-memory
    effect: allow
---

<!-- home/dot_config/opencode/agents/dotfiles-demo.md -->
# Demo

Read showcase.md once, then describe three useful features in at most 60 words.
Use only the read tool. Do not explore, load skills, delegate, or retry a failed
read. If reading fails, explain the failure briefly and stop.
