// scripts/ts-syntax.js
// Parse-check TypeScript files and report syntax errors.
//
// The OpenCode notifier plugin (home/dot_config/opencode/plugin/notify.ts) had
// no gate of any kind: nothing in pre-commit reads TypeScript, so a parse error
// would install cleanly via chezmoi and only surface at runtime, inside a plugin
// host that swallows plugin errors by design. That is a silent failure mode,
// which is the same class of bug the plugin itself was written to avoid.
//
// SYNTAX ONLY, not a type-check, and the distinction is deliberate. Full
// checking needs @types/node resolvable from the file's own directory, which
// means vendoring type packages into the dotfiles repo purely to satisfy a lint
// hook. The compiler's parser gives us the real win (malformed code cannot ship)
// with one dependency and no project scaffolding. It will not catch a type error.

const fs = require("node:fs")
const ts = require("typescript")

const files = process.argv.slice(2)
let failed = 0

for (const file of files) {
  let text
  try {
    text = fs.readFileSync(file, "utf8")
  } catch (err) {
    console.error(`ts-syntax: cannot read ${file}: ${err.message}`)
    failed = 1
    continue
  }

  const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, false, ts.ScriptKind.TS)
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

process.exit(failed)
