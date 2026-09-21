// scripts/ts-syntax.js
// Parse-check TypeScript files and exercise the OpenCode notifier plugin.
//
// OpenCode plugins would otherwise install cleanly via chezmoi and surface parse
// errors only at runtime, inside a plugin host. Cover both plain TypeScript and
// TSX used by the V2 terminal plugin API.
//
// SYNTAX ONLY, not a type-check, and the distinction is deliberate. Full
// checking needs @types/node resolvable from the file's own directory, which
// means vendoring type packages into the dotfiles repo purely to satisfy a lint
// hook. The compiler's parser gives us the real win (malformed code cannot ship)
// with one dependency and no project scaffolding. It will not catch a type error.

const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const ts = require("typescript")
const { verifyNotifyPlugin } = require("../tests/test_opencode_notify_plugin.js")

const files = process.argv.slice(2)
let failed = 0

async function main() {
  for (const file of files) {
    let text
    try {
      text = fs.readFileSync(file, "utf8")
      if (file.endsWith(".tmpl")) {
        const source = path.resolve(__dirname, "..")
        text = execFileSync("chezmoi", ["execute-template", "--source", source], {
          input: text,
          encoding: "utf8",
        })
      }
    } catch (err) {
      console.error(`ts-syntax: cannot read ${file}: ${err.message}`)
      failed = 1
      continue
    }

    const kind = file.endsWith(".tsx") || file.endsWith(".tsx.tmpl") ? ts.ScriptKind.TSX : ts.ScriptKind.TS
    const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, false, kind)
    // parseDiagnostics is not on the public type but is present on the node and is
    // the only way to get parser errors without a full Program.
    const diagnostics = source.parseDiagnostics || []

    for (const d of diagnostics) {
      const { line, character } = source.getLineAndCharacterOfPosition(d.start)
      const message = ts.flattenDiagnosticMessageText(d.messageText, " ")
      console.error(`${file}(${line + 1},${character + 1}): error TS${d.code}: ${message}`)
      failed = 1
    }
  }

  const repo = path.resolve(__dirname, "..")
  const notifier = path.join(repo, "home/dot_config/opencode/plugin/notify.ts")
  try {
    await verifyNotifyPlugin(ts, notifier)
  } catch (err) {
    console.error(`opencode-notify-plugin: ${err.stack || err.message}`)
    failed = 1
  }

  process.exitCode = failed
}

void main()
