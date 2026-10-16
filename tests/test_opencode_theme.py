# tests/test_opencode_theme.py
"""Tests for the native OpenCode V2 gud-lucent theme.

home/dot_config/opencode/themes/gud-lucent.json.tmpl renders a V2 theme
document from two committed data files: the palette catalog and the hue scales
that scripts/build-opencode-theme.py generates from it. Plugins such as the
footer read colors only from OpenCode's resolved theme, so the document has to
carry the exact palette colors.

Every catalog palette is rendered through real chezmoi into a disposable
config. A small resolver follows the V2 reference rules (base merged with the
mode block, hue aliases, $hue.<name>.<step>, $token.path, and "transparent")
so the semantic tokens can be checked without Node or @opencode/theme. The
Node suite in test_opencode_theme.mjs resolves the same documents through the
real package when it is available.
"""
import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).parent.parent
SOURCE = REPO / "home"
TEMPLATE = SOURCE / "dot_config" / "opencode" / "themes" / "gud-lucent.json.tmpl"
GENERATOR = REPO / "scripts" / "build-opencode-theme.py"

STEPS = ("100", "200", "300", "400", "500", "600", "700", "800", "900")
NAMED_HUES = ("red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink")
NEUTRAL = {"200": "foreground", "400": "comment", "600": "selection",
           "700": "surface", "800": "background"}
HEX6 = re.compile(r"^#[0-9a-f]{6}$")
HEX_ANY = re.compile(r"^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$", re.IGNORECASE)
HUE_STEP_REF = re.compile(r"^\$hue\.(.+)\.(100|200|300|400|500|600|700|800|900)$")
TRANSPARENT = "transparent"


def load_generator():
    spec = importlib.util.spec_from_file_location("build_opencode_theme", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def merge(base, override):
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = merge(result[key], value)
        else:
            result[key] = value
    return result


class Resolver:
    """Resolve color references the way @opencode/theme resolveThemeDocument does."""

    def __init__(self, document, mode="dark"):
        modes = [m for m in ("light", "dark") if m in document]
        if not modes:
            raise AssertionError("theme document has no light or dark block")
        self.mode = mode if mode in modes else modes[0]
        self.theme = merge(document["base"], document[self.mode])
        self.hue = {name: self._scale(name, ()) for name in self.theme["hue"]}

    def _scale(self, name, stack):
        if name in stack:
            raise AssertionError(f"circular hue alias: {stack + (name,)}")
        value = self.theme["hue"].get(name)
        if isinstance(value, str):
            match = re.match(r"^\$hue\.([^.]+)$", value)
            if not match:
                raise AssertionError(f"hue {name} alias {value!r} is not $hue.<name>")
            return self._scale(match.group(1), stack + (name,))
        if not isinstance(value, dict) or set(value) != set(STEPS):
            raise AssertionError(f"hue {name} must define exactly steps {STEPS}")
        for step, color in value.items():
            if not HEX_ANY.match(color):
                raise AssertionError(f"hue.{name}.{step} is not a hex color: {color!r}")
        return {step: value[step].lower() for step in STEPS}

    def color(self, value, stack=()):
        if value == TRANSPARENT:
            return TRANSPARENT
        if not isinstance(value, str):
            raise AssertionError(f"not a color value: {value!r}")
        if HEX_ANY.match(value):
            return value.lower()
        if not value.startswith("$"):
            raise AssertionError(f"invalid color {value!r}")
        target = value[1:]
        if target in stack:
            raise AssertionError(f"circular reference: {stack + (target,)}")
        match = HUE_STEP_REF.match(value)
        if match:
            return self.hue[match.group(1)][match.group(2)]
        node = {**self.theme, "hue": self.hue}
        for key in target.split("."):
            if not isinstance(node, dict) or key not in node:
                raise AssertionError(f"reference {value!r} was not found")
            node = node[key]
        return self.color(node, stack + (target,))

    def token(self, path):
        node = self.theme
        for key in path.split("."):
            node = node[key]
        return self.color(node)


def walk(tree, prefix=""):
    for key, value in tree.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            yield from walk(value, path)
        else:
            yield path, value


class OpenCodeThemeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which("chezmoi") is None:
            raise RuntimeError("chezmoi is required to render gud-lucent.json.tmpl")
        cls.order, cls.palettes = load_generator().parse_catalog(
            SOURCE / ".chezmoidata" / "palettes.yaml")
        cls.documents = {}
        with tempfile.TemporaryDirectory() as tmp:
            for palette in cls.order:
                config = Path(tmp) / palette / "chezmoi.toml"
                config.parent.mkdir()
                config.write_text(f'[data]\npalette = "{palette}"\n', encoding="utf-8")
                rendered = subprocess.run(
                    ["chezmoi", "execute-template", "--source", str(REPO),
                     "--config", str(config)],
                    input=TEMPLATE.read_text(encoding="utf-8"),
                    capture_output=True, text=True, check=True,
                ).stdout
                cls.documents[palette] = json.loads(rendered)

    def test_catalog_covers_every_palette(self):
        self.assertTrue(self.order)
        self.assertEqual(sorted(self.documents), sorted(self.order))

    def test_document_uses_the_v2_shape(self):
        # OpenCode 2.0.29 migrates any theme file with a top-level "theme" key
        # as V1 and parses the rest as V2, so that key must never appear.
        for palette, document in self.documents.items():
            with self.subTest(palette=palette):
                self.assertNotIn("theme", document)
                self.assertNotIn("defs", document)
                mode = self.palettes[palette].get("variant", "dark")
                self.assertEqual(set(document) - {"$schema"}, {"base", mode})
                self.assertIn("hue", document[mode])
                self.assertNotIn("hue", document["base"])

    def test_hue_scales_keep_exact_palette_colors(self):
        for palette, document in self.documents.items():
            colors = self.palettes[palette]["colors"]
            resolver = Resolver(document)
            with self.subTest(palette=palette):
                for name in NAMED_HUES:
                    self.assertEqual(resolver.hue[name]["200"], colors[name], name)
                for step, key in NEUTRAL.items():
                    self.assertEqual(resolver.hue["neutral"][step], colors[key], step)
                for name, scale in resolver.hue.items():
                    for step, color in scale.items():
                        self.assertRegex(color, HEX6, f"hue.{name}.{step}")
                self.assertEqual(resolver.hue["accent"], resolver.hue["pink"])
                self.assertEqual(resolver.hue["interactive"], resolver.hue["purple"])

    def test_semantic_tokens_resolve_to_the_palette(self):
        for palette, document in self.documents.items():
            colors = self.palettes[palette]["colors"]
            resolver = Resolver(document)
            expected = {
                "text.base": colors["foreground"],
                "text.muted": colors["comment"],
                "text.feedback.error.base": colors["red"],
                "text.feedback.warning.base": colors["orange"],
                "text.feedback.success.base": colors["green"],
                "text.feedback.info.base": colors["blue"],
                "diff.background.context": colors["surface"],
                "border.base": colors["selection"],
                "syntax.keyword": colors["purple"],
                "syntax.string": colors["yellow"],
                "syntax.type": colors["cyan"],
                "markdown.linkText": colors["pink"],
                "background.action.primary.$focused": colors["purple"],
            }
            with self.subTest(palette=palette):
                for path, color in expected.items():
                    self.assertEqual(resolver.token(path), color, path)
                for path in ("background.base", "background.raised.base",
                             "background.raised.high", "background.raised.max"):
                    self.assertEqual(resolver.token(path), TRANSPARENT, path)

    def test_light_requests_fall_back_to_the_palette_mode(self):
        for palette, document in self.documents.items():
            with self.subTest(palette=palette):
                resolver = Resolver(document, mode="light")
                self.assertEqual(resolver.token("text.base"),
                                 self.palettes[palette]["colors"]["foreground"])

    def test_every_token_resolves(self):
        for palette, document in self.documents.items():
            resolver = Resolver(document)
            with self.subTest(palette=palette):
                tokens = {k: v for k, v in resolver.theme.items()
                          if k not in ("hue", "categorical")}
                for path, value in walk(tokens):
                    resolver.color(value)
                    if path.startswith(("syntax.", "markdown.")):
                        # Syntax and markdown accept only hex or hue-step refs.
                        self.assertTrue(HEX_ANY.match(value) or HUE_STEP_REF.match(value), path)

    def test_categorical_entries_are_distinct_hues(self):
        for palette, document in self.documents.items():
            resolver = Resolver(document)
            categorical = document["base"]["categorical"]
            with self.subTest(palette=palette):
                self.assertTrue(categorical)
                swatches = [resolver.hue[name]["200"] for name in categorical]
                self.assertEqual(len(swatches), len(set(swatches)))


if __name__ == "__main__":
    unittest.main()
