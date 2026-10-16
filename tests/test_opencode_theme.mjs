// tests/test_opencode_theme.mjs
// Resolve every rendered gud-lucent document through @opencode/theme, the
// package OpenCode V2 uses for themes, and compare the result with the palette.
//
// The package is not a repository dependency. Point OPENCODE_THEME_MODULE at an
// installed @opencode/theme package directory to run this suite; without it the
// suite skips with that reason. tests/test_opencode_theme.py covers the same
// contract in CI with a stdlib resolver.
import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { fileURLToPath, pathToFileURL } from "node:url"

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const TEMPLATE = path.join(REPO, "home/dot_config/opencode/themes/gud-lucent.json.tmpl")
const NAMED_HUES = ["red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"]

async function loadThemePackage() {
  const dir = process.env.OPENCODE_THEME_MODULE
  if (dir) {
    const entry = path.join(path.resolve(dir), "dist/tui/index.js")
    if (!existsSync(entry)) return { reason: `OPENCODE_THEME_MODULE has no dist/tui/index.js: ${dir}` }
    return { module: await import(pathToFileURL(entry).href) }
  }
  try {
    return { module: await import("@opencode/theme/tui") }
  } catch {
    return { reason: "@opencode/theme is not installed; set OPENCODE_THEME_MODULE to its package directory" }
  }
}

function chezmoi(config, template) {
  return execFileSync("chezmoi", ["execute-template", "--source", REPO, "--config", config], {
    input: template,
    encoding: "utf8",
  })
}

function hex(rgba) {
  const [r, g, b, a] = rgba.toInts()
  const rgb = `#${[r, g, b].map((v) => v.toString(16).padStart(2, "0")).join("")}`
  return a === 255 ? rgb : `${rgb}${a.toString(16).padStart(2, "0")}`
}

const { module: theme, reason } = await loadThemePackage()

test("gud-lucent resolves to exact palette colors through @opencode/theme", { skip: reason ?? false }, () => {
  const tmp = mkdtempSync(path.join(tmpdir(), "gud-lucent-"))
  try {
    const config = path.join(tmp, "chezmoi.toml")
    writeFileSync(config, '[data]\npalette = "dracula"\n')
    const catalog = JSON.parse(chezmoi(config, "{{ dict \"order\" .paletteOrder \"palettes\" .palettes | toJson }}"))
    const template = readFileSync(TEMPLATE, "utf8")
    assert.ok(catalog.order.length > 0)

    for (const id of catalog.order) {
      const colors = catalog.palettes[id].colors
      writeFileSync(config, `[data]\npalette = "${id}"\n`)
      const raw = JSON.parse(chezmoi(config, template))
      // OpenCode 2.0.29 sends documents with a top-level "theme" key through
      // migrateV1 and parses the rest with parseThemeDocument.
      assert.equal("theme" in raw, false, `${id}: V1 "theme" key`)
      assert.ok("base" in raw, `${id}: missing base`)
      const document = theme.parseThemeDocument(raw, "gud-lucent")

      for (const mode of ["dark", "light"]) {
        const t = theme.resolveThemeDocument(document, mode)
        const at = `${id} (${mode})`
        for (const name of NAMED_HUES) assert.equal(hex(t.hue[name][200]), colors[name], `${at} hue.${name}.200`)
        assert.equal(hex(t.hue.accent[200]), colors.pink, `${at} hue.accent.200`)
        assert.equal(hex(t.hue.interactive[200]), colors.purple, `${at} hue.interactive.200`)
        assert.equal(hex(t.hue.neutral[200]), colors.foreground, `${at} hue.neutral.200`)
        assert.equal(hex(t.hue.neutral[400]), colors.comment, `${at} hue.neutral.400`)
        assert.equal(hex(t.hue.neutral[600]), colors.selection, `${at} hue.neutral.600`)
        assert.equal(hex(t.hue.neutral[700]), colors.surface, `${at} hue.neutral.700`)
        assert.equal(hex(t.hue.neutral[800]), colors.background, `${at} hue.neutral.800`)
        assert.equal(hex(t.text.base), colors.foreground, `${at} text.base`)
        assert.equal(hex(t.text.muted), colors.comment, `${at} text.muted`)
        assert.equal(hex(t.text.feedback.error.base), colors.red, `${at} feedback.error`)
        assert.equal(hex(t.text.feedback.warning.base), colors.orange, `${at} feedback.warning`)
        assert.equal(hex(t.text.feedback.success.base), colors.green, `${at} feedback.success`)
        assert.equal(hex(t.text.feedback.info.base), colors.blue, `${at} feedback.info`)
        assert.equal(hex(t.diff.background.context), colors.surface, `${at} diff.background.context`)
        for (const surface of ["base", "high", "max"]) {
          assert.equal(t.background.raised[surface].toInts()[3], 0, `${at} background.raised.${surface}`)
        }
        assert.equal(t.background.base.toInts()[3], 0, `${at} background.base`)
        // References keep hue identity, so plugins can step a token's color.
        assert.deepEqual(t.source(t.text.feedback.error.base), { hue: "red", step: 200 }, `${at} source`)
      }
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true })
  }
})
