#!/usr/bin/env python3
# scripts/build-opencode-theme.py
#
# Authoring-time generator. Reads the committed palette catalog
# (home/.chezmoidata/palettes.yaml) and writes the OpenCode V2 hue data that
# home/dot_config/opencode/themes/gud-lucent.json.tmpl renders:
# home/.chezmoidata/opencode-theme.yaml.
#
# A chezmoi template cannot do OKLCH math, so the nine-step scales are
# precomputed here. Each named hue (red, orange, yellow, green, cyan, blue,
# purple, pink) keeps the exact palette color at step 200. The gray scale is
# anchored to foreground (200), comment (400), selection (600), surface (700),
# and background (800). The remaining steps use the same OKLCH ramps that
# OpenCode 2.0.29 applies when it migrates a V1 theme, so shading matches the
# built-in themes' direction: dark modes run light at 100 to dark at 900.
#
# This NEVER runs at chezmoi apply/init. The input is the committed catalog,
# not the scheme submodule, so --check always runs, locally and in CI.
#
# Stdlib only. Full guide: docs/palettes.md.

import argparse
import math
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PALETTES = os.path.join(REPO, "home", ".chezmoidata", "palettes.yaml")
DEFAULT_OUT = os.path.join(REPO, "home", ".chezmoidata", "opencode-theme.yaml")

USAGE_EXAMPLES = """\
examples:
  # regenerate after palettes.yaml changes
  python3 scripts/build-opencode-theme.py

  # drift gate: exit non-zero if the committed hue data is stale
  python3 scripts/build-opencode-theme.py --check

when to run:
  After scripts/build-palettes.py rewrites palettes.yaml, or after changing
  the scale rules in this script. prek and CI run --check. Full guide:
  docs/palettes.md.
"""

STEPS = (100, 200, 300, 400, 500, 600, 700, 800, 900)
# Palette keys that become hue scales of the same name.
HUES = ("red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink")
# Gray anchors: step -> palette key. The theme aliases neutral to gray.
NEUTRAL_ANCHORS = ((200, "foreground"), (400, "comment"), (600, "selection"),
                   (700, "surface"), (800, "background"))
# Agent and repeated-item colors, in the order OpenCode's V1 migration uses
# for the roles gud-lucent assigns: secondary, accent, success, warning,
# primary, error, info. A hue whose step 200 repeats an earlier one is dropped
# so two entries never render the same color.
CATEGORICAL = ("cyan", "pink", "green", "orange", "purple", "red", "blue")


# ---- color math (mirrors @opencode/theme 2.0.29 color.js) -------------------

def _js_round(value):
    """JavaScript Math.round for the non-negative channel values used here."""
    return int(math.floor(value + 0.5))


def _hex_to_rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def _srgb_to_linear(value):
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def _linear_to_srgb(value):
    if value <= 0.0031308:
        return value * 12.92
    return 1.055 * value ** (1 / 2.4) - 0.055


def to_oklch(color):
    red, green, blue = (_srgb_to_linear(c / 255) for c in _hex_to_rgb(color))
    l_root = math.cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    m_root = math.cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    s_root = math.cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    lightness = 0.2104542553 * l_root + 0.793617785 * m_root - 0.0040720468 * s_root
    a = 1.9779984951 * l_root - 2.428592205 * m_root + 0.4505937099 * s_root
    b = 0.0259040371 * l_root + 0.7827717662 * m_root - 0.808675766 * s_root
    angle = math.degrees(math.atan2(b, a))
    return lightness, math.sqrt(a * a + b * b), angle + 360 if angle < 0 else angle


def _oklch_to_rgb(lightness, chroma, hue):
    a = chroma * math.cos(math.radians(hue))
    b = chroma * math.sin(math.radians(hue))
    l_root = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_root = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_root = lightness - 0.0894841775 * a - 1.291485548 * b
    l, m, s = l_root ** 3, m_root ** 3, s_root ** 3
    return (
        _linear_to_srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
        _linear_to_srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
        _linear_to_srgb(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    )


def _in_gamut(rgb):
    return all(0 <= c <= 1 for c in rgb)


def oklch_to_hex(lightness, chroma, hue):
    """Reduce chroma until the color fits sRGB, as OpenCode's fitOklch does."""
    lightness = min(1, max(0, lightness))
    chroma = max(0, chroma)
    hue = ((hue % 360) + 360) % 360
    rgb = _oklch_to_rgb(lightness, chroma, hue)
    if not _in_gamut(rgb):
        for index in range(24):
            rgb = _oklch_to_rgb(lightness, chroma * 0.9 ** (index + 1), hue)
            if _in_gamut(rgb):
                break
        else:
            rgb = _oklch_to_rgb(lightness, 0, hue)
    return "#" + "".join(f"{_js_round(min(1, max(0, c)) * 255):02x}" for c in rgb)


def hue_scale(color, mode):
    """Nine steps with the palette color at 200, fading toward the mode's end."""
    lightness, chroma, hue = to_oklch(color)
    endpoint = max(0.97, lightness) if mode == "light" else min(0.18, lightness)
    scale = {}
    for step in STEPS:
        if step == 200:
            scale[step] = color
            continue
        progress = (step - 200) / (900 - 200)
        scale[step] = oklch_to_hex(lightness + (endpoint - lightness) * progress,
                                   chroma * (1 - progress * 0.5), hue)
    return scale


def _interpolate(first, second, amount):
    start, end = to_oklch(first), to_oklch(second)
    turn = (((end[2] - start[2]) % 360) + 540) % 360 - 180
    return oklch_to_hex(start[0] + (end[0] - start[0]) * amount,
                        start[1] + (end[1] - start[1]) * amount,
                        start[2] + turn * amount)


def neutral_scale(colors):
    """Exact anchors, OKLCH interpolation between them, extrapolation at ends."""
    anchors = [(step, colors[key]) for step, key in NEUTRAL_ANCHORS]
    scale = {}
    for step in STEPS:
        exact = [color for anchor, color in anchors if anchor == step]
        if exact:
            scale[step] = exact[0]
            continue
        if step < anchors[0][0]:
            lower, upper = anchors[0], anchors[1]
        elif step > anchors[-1][0]:
            lower, upper = anchors[-2], anchors[-1]
        else:
            lower = [a for a in anchors if a[0] < step][-1]
            upper = [a for a in anchors if a[0] > step][0]
        amount = (step - lower[0]) / (upper[0] - lower[0])
        scale[step] = _interpolate(lower[1], upper[1], amount)
    return scale


def contrast_text(color):
    """Black or white text on a filled color, matching OpenCode's V1 rule for
    selected and destructive actions when the theme background is transparent."""
    red, green, blue = (c / 255 for c in _hex_to_rgb(color))
    return "#000000" if 0.299 * red + 0.587 * green + 0.114 * blue > 0.5 else "#ffffff"


# ---- catalog parsing -------------------------------------------------------

def parse_catalog(path):
    """Read paletteOrder, variant, and colors from the generated catalog.

    palettes.yaml is emitted by build-palettes.py in a fixed two-space layout,
    so a small line parser is enough and keeps this script stdlib-only.
    """
    order, palettes = [], {}
    section = palette = block = None
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            indent = len(line) - len(line.lstrip(" "))
            text = line.strip()
            if indent == 0:
                section = text.rstrip(":")
                continue
            if section == "paletteOrder" and indent == 2 and text.startswith("- "):
                order.append(text[2:].strip())
            elif section == "palettes" and indent == 2:
                palette = text.rstrip(":")
                palettes[palette] = {"colors": {}}
                block = None
            elif section == "palettes" and indent == 4:
                key, _, value = text.partition(":")
                block = key
                if value.strip():
                    palettes[palette][key] = value.strip().strip('"')
            elif section == "palettes" and indent == 6 and block == "colors":
                m = re.match(r'^(\w+):\s*"(#[0-9a-f]{6})"$', text)
                if not m:
                    raise SystemExit(f"{path}: unexpected color line: {text}")
                palettes[palette]["colors"][m.group(1)] = m.group(2)
    if not order:
        raise SystemExit(f"{path}: no paletteOrder entries")
    for pid in order:
        if pid not in palettes:
            raise SystemExit(f"{path}: paletteOrder names missing palette {pid}")
        needed = set(HUES) | {key for _, key in NEUTRAL_ANCHORS}
        missing = sorted(needed - set(palettes[pid]["colors"]))
        if missing:
            raise SystemExit(f"{path}: {pid} is missing colors {missing}")
    return order, palettes


# ---- build and emit --------------------------------------------------------

def build(order, palettes):
    entries = []
    for pid in order:
        colors = palettes[pid]["colors"]
        mode = palettes[pid].get("variant", "dark")
        if mode not in ("dark", "light"):
            raise SystemExit(f"{pid}: unsupported variant {mode}")
        hue = {"gray": neutral_scale(colors)}
        for name in HUES:
            hue[name] = hue_scale(colors[name], mode)
        categorical, seen = [], set()
        for name in CATEGORICAL:
            if colors[name] not in seen:
                categorical.append(name)
                seen.add(colors[name])
        on = {name: contrast_text(colors[name]) for name in HUES}
        entries.append({"id": pid, "mode": mode, "hue": hue,
                        "categorical": categorical, "on": on})
    return entries


def emit_yaml(entries):
    out = [
        "# home/.chezmoidata/opencode-theme.yaml",
        "# Generated by scripts/build-opencode-theme.py from palettes.yaml.",
        "# Do not edit by hand. Rerun the generator after the palette catalog",
        "# changes, and commit. gud-lucent.json.tmpl reads one entry through",
        "# data.palette.",
        "",
        "opencodeTheme:",
    ]
    for e in entries:
        out.append(f"  {e['id']}:")
        out.append(f"    mode: {e['mode']}")
        out.append("    categorical: [" + ", ".join(e["categorical"]) + "]")
        out.append("    on:")
        for name in HUES:
            out.append(f'      {name}: "{e["on"][name]}"')
        out.append("    hue:")
        for name in ("gray",) + HUES:
            out.append(f"      {name}:")
            for step in STEPS:
                out.append(f'        "{step}": "{e["hue"][name][step]}"')
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(
        prog="build-opencode-theme.py",
        description="Generate OpenCode V2 hue scales from the committed palette catalog.",
        epilog=USAGE_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--palettes", default=DEFAULT_PALETTES,
                    help="palette catalog to read (default: home/.chezmoidata/palettes.yaml)")
    ap.add_argument("--out", default=DEFAULT_OUT,
                    help="hue data to write (default: home/.chezmoidata/opencode-theme.yaml)")
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if the committed hue data differs from a fresh generation")
    args = ap.parse_args()

    entries = build(*parse_catalog(args.palettes))
    text = emit_yaml(entries)
    if args.check:
        current = open(args.out, encoding="utf-8").read() if os.path.exists(args.out) else ""
        if current != text:
            print(f"opencode theme drift in: {args.out}", file=sys.stderr)
            print("run: python3 scripts/build-opencode-theme.py", file=sys.stderr)
            return 1
        print("opencode theme hue data up to date")
        return 0

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"wrote {len(entries)} palettes to {os.path.relpath(args.out, REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
