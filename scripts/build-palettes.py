#!/usr/bin/env python3
# scripts/build-palettes.py
#
# Authoring-time generator. Reads base16/base24 scheme YAMLs from the
# tinted-theming/schemes submodule and writes the committed catalog
# .chezmoidata/palettes.yaml plus the palette picker list in .chezmoi.toml.tmpl.
#
# This NEVER runs at chezmoi apply/init. Downstream machines render the committed
# YAML with zero Python, zero submodule, zero network. Run it here, commit the
# output. CI runs it with --check to catch drift from upstream schemes.
#
# Stdlib only (colorsys, argparse, re). Scheme YAMLs are flat enough to parse
# without PyYAML, and the catalog is hand-emitted to match the file's style.
#
# Full guide, mapping reference, and the add-a-scheme workflow: docs/palettes.md.
# `python3 scripts/build-palettes.py --help` prints the CLI examples below.

import argparse
import colorsys
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SCHEMES = os.path.join(REPO, "vendor", "tinted-schemes")
DEFAULT_OUT = os.path.join(REPO, ".chezmoidata", "palettes.yaml")
DEFAULT_TOML = os.path.join(REPO, ".chezmoi.toml.tmpl")

USAGE_EXAMPLES = """\
examples:
  # regenerate the catalog after editing CURATED or bumping the submodule
  python3 scripts/build-palettes.py

  # CI drift gate: exit non-zero if the committed catalog is stale
  # (skips cleanly when the vendor/tinted-schemes submodule is absent)
  python3 scripts/build-palettes.py --check

  # generate from a schemes checkout outside the submodule path
  python3 scripts/build-palettes.py --schemes-dir /path/to/tinted-theming-schemes

when to run:
  Authoring time only, never at chezmoi apply/init. Run it when you edit the
  CURATED list or bump the vendor/tinted-schemes submodule. CI runs --check on
  every push to catch drift. Full guide: docs/palettes.md.
"""

# Curated catalog: (output_id, display_name, source_relpath).
# output_id is what data.palette stores and what the picker shows. The first
# entry is the default. gruvbox-dark and tokyo-night keep their historical ids
# so persisted selections do not break, while sourcing from the tinted-theming
# scheme file named on the right.
CURATED = [
    ("dracula", "Dracula", "base16/dracula.yaml"),
    ("catppuccin-mocha", "Catppuccin Mocha", "base16/catppuccin-mocha.yaml"),
    ("catppuccin-macchiato", "Catppuccin Macchiato", "base16/catppuccin-macchiato.yaml"),
    ("catppuccin-frappe", "Catppuccin Frappe", "base16/catppuccin-frappe.yaml"),
    ("gruvbox-dark", "Gruvbox Dark", "base16/gruvbox-dark-medium.yaml"),
    ("gruvbox-dark-hard", "Gruvbox Dark Hard", "base16/gruvbox-dark-hard.yaml"),
    ("gruvbox-material", "Gruvbox Material", "base16/gruvbox-material-dark-medium.yaml"),
    ("tokyo-night", "Tokyo Night", "base16/tokyo-night-storm.yaml"),
    ("nord", "Nord", "base16/nord.yaml"),
    ("rose-pine", "Rose Pine", "base16/rose-pine.yaml"),
    ("rose-pine-moon", "Rose Pine Moon", "base16/rose-pine-moon.yaml"),
    ("everforest", "Everforest", "base16/everforest.yaml"),
    ("kanagawa", "Kanagawa", "base16/kanagawa.yaml"),
    ("onedark", "One Dark", "base16/onedark.yaml"),
    ("solarized-dark", "Solarized Dark", "base16/solarized-dark.yaml"),
]

BEGIN = "GENERATED-PALETTES-BEGIN"
END = "GENERATED-PALETTES-END"


# ---- color helpers ---------------------------------------------------------

def _hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*(max(0, min(255, round(c))) for c in rgb))


def norm(h):
    """Normalize to lowercase #rrggbb."""
    return _rgb_to_hex(_hex_to_rgb(h))


def lighten(h, amount=0.12):
    """Lighten a color by raising HLS lightness, for base16 bright ANSI slots."""
    r, g, b = (c / 255 for c in _hex_to_rgb(h))
    hue, lig, sat = colorsys.rgb_to_hls(r, g, b)
    lig = min(0.92, lig + amount)
    r, g, b = colorsys.hls_to_rgb(hue, lig, sat)
    return _rgb_to_hex((r * 255, g * 255, b * 255))


def blend(fg, bg, alpha):
    """alpha*fg + (1-alpha)*bg in sRGB. Used for notify background tints."""
    f, b = _hex_to_rgb(fg), _hex_to_rgb(bg)
    return _rgb_to_hex(tuple(f[i] * alpha + b[i] * (1 - alpha) for i in range(3)))


def _rel_lum(h):
    def chan(c):
        c /= 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (chan(c) for c in _hex_to_rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = _rel_lum(a), _rel_lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def notify_tint(accent, base00):
    """Dark background chip: blend accent toward base00, then darken until the
    accent clears ~3:1 against it (legibility guard)."""
    alpha = 0.20
    tint = blend(accent, base00, alpha)
    while contrast(accent, tint) < 3.0 and alpha > 0.04:
        alpha -= 0.02
        tint = blend(accent, base00, alpha)
    return tint


# ---- scheme parsing --------------------------------------------------------

def parse_scheme(path):
    """Minimal parser for a tinted-theming scheme YAML (flat key: "value")."""
    meta = {}
    palette = {}
    in_palette = False
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if re.match(r"^\S", line):
                in_palette = line.strip().startswith("palette:")
                m = re.match(r'^(\w+):\s*"?([^"\n]*)"?\s*$', line.strip())
                if m and not in_palette:
                    meta[m.group(1)] = m.group(2)
                continue
            if in_palette:
                m = re.match(r'^\s+(base[0-9A-Fa-f]{2}):\s*"?(#?[0-9A-Fa-f]{6})"?', line)
                if m:
                    palette[m.group(1).lower()] = norm(m.group(2))
    return meta, palette


def to_entry(out_id, name, meta, b):
    """Map base16/base24 -> the semantic catalog contract."""
    is24 = "base12" in b
    ansi = [
        b["base00"], b["base08"], b["base0b"], b["base0a"],
        b["base0d"], b["base0e"], b["base0c"], b["base05"],
        b["base03"],
        b["base12"] if is24 else lighten(b["base08"]),
        b["base14"] if is24 else lighten(b["base0b"]),
        b["base13"] if is24 else lighten(b["base0a"]),
        b["base16"] if is24 else lighten(b["base0d"]),
        b["base17"] if is24 else lighten(b["base0e"]),
        b["base15"] if is24 else lighten(b["base0c"]),
        b["base07"],
    ]
    # base16 intends base00<base01<base02 in lightness, but some schemes set
    # base01 darker than the background. Surface must sit above the background,
    # so fall back to base02 when base01 would be darker.
    surface = b["base01"] if _rel_lum(b["base01"]) > _rel_lum(b["base00"]) else b["base02"]
    colors = {
        "background": b["base00"], "surface": surface, "selection": b["base02"],
        "foreground": b["base05"], "comment": b["base03"], "cursor": b["base05"],
        "black": b["base00"], "red": b["base08"], "green": b["base0b"],
        "yellow": b["base0a"], "blue": b["base0d"], "purple": b["base0e"],
        "cyan": b["base0c"], "white": b["base05"], "orange": b["base09"],
        "pink": b["base0e"],
    }
    notify = {
        "dark_red": notify_tint(b["base08"], b["base00"]),
        "dark_purple": notify_tint(b["base0e"], b["base00"]),
        "dark_green": notify_tint(b["base0b"], b["base00"]),
        "dark_orange": notify_tint(b["base09"], b["base00"]),
        "dark_cyan": notify_tint(b["base0c"], b["base00"]),
        "dark_pink": notify_tint(b["base0e"], b["base00"]),
    }
    base16 = {k: b[k] for k in [f"base0{c}" for c in "0123456789"] + [f"base0{c}" for c in "abcdef"]}
    return {"id": out_id, "name": name, "system": meta.get("system", "base16"),
            "variant": meta.get("variant", "dark"), "base16": base16,
            "colors": colors, "ansi": ansi, "notify": notify}


# ---- emitters --------------------------------------------------------------

CATALOG_KEYS_16 = [f"base0{c}" for c in "0123456789abcdef"]
SEMANTIC_ORDER = ["background", "surface", "selection", "foreground", "comment",
                  "cursor", "black", "red", "green", "yellow", "blue", "purple",
                  "cyan", "white", "orange", "pink"]
NOTIFY_ORDER = ["dark_red", "dark_purple", "dark_green", "dark_orange",
                "dark_cyan", "dark_pink"]


def emit_yaml(entries):
    out = []
    out.append("# .chezmoidata/palettes.yaml")
    out.append("# Generated by scripts/build-palettes.py from vendor/tinted-schemes.")
    out.append("# Do not edit by hand. Add a scheme to CURATED in the generator, rerun it,")
    out.append("# and commit. Consumers select one entry through data.palette.")
    out.append("")
    out.append("paletteOrder:")
    for e in entries:
        out.append(f"  - {e['id']}")
    out.append("")
    out.append("palettes:")
    for e in entries:
        out.append(f"  {e['id']}:")
        out.append(f"    name: {e['name']}")
        out.append(f"    system: {e['system']}")
        out.append(f"    variant: {e['variant']}")
        out.append("    base16:")
        for k in CATALOG_KEYS_16:
            out.append(f'      {k}: "{e["base16"][k]}"')
        out.append("    colors:")
        for k in SEMANTIC_ORDER:
            out.append(f'      {k}: "{e["colors"][k]}"')
        out.append("    ansi:")
        for c in e["ansi"]:
            out.append(f'      - "{c}"')
        out.append("    notify:")
        for k in NOTIFY_ORDER:
            out.append(f'      {k}: "{e["notify"][k]}"')
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def emit_palettedefs(entries):
    lines = [f"{{{{- /* {BEGIN} (scripts/build-palettes.py; do not edit by hand) */ -}}}}",
             "{{- $paletteDefs := list"]
    for e in entries:
        lines.append(f'    (dict "id" "{e["id"]}" "name" "{e["name"]}")')
    lines.append("-}}")
    lines.append(f"{{{{- /* {END} */ -}}}}")
    return "\n".join(lines)


def rewrite_markers(toml_text, block):
    # Replace the whole marker-to-marker region.
    region = re.compile(
        r"\{\{- /\* " + BEGIN + r".*?" + END + r" \*/ -\}\}",
        re.DOTALL,
    )
    if not region.search(toml_text):
        raise SystemExit(
            f"marker block not found in TOML; add the {BEGIN}/{END} markers first")
    return region.sub(lambda _: block, toml_text)


# ---- main ------------------------------------------------------------------

def build(schemes_dir):
    entries = []
    for out_id, name, rel in CURATED:
        path = os.path.join(schemes_dir, rel)
        if not os.path.exists(path):
            raise SystemExit(f"missing scheme: {path}")
        meta, palette = parse_scheme(path)
        missing = [k for k in CATALOG_KEYS_16 if k not in palette]
        if missing:
            raise SystemExit(f"{rel}: missing base keys {missing}")
        entries.append(to_entry(out_id, name, meta, palette))
    return entries


def main():
    ap = argparse.ArgumentParser(
        prog="build-palettes.py",
        description="Generate the committed palette catalog from base16 schemes.",
        epilog=USAGE_EXAMPLES,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--schemes-dir", default=DEFAULT_SCHEMES,
                    help="tinted-theming/schemes checkout (default: the vendored submodule)")
    ap.add_argument("--out", default=DEFAULT_OUT,
                    help="catalog to write (default: .chezmoidata/palettes.yaml)")
    ap.add_argument("--toml", default=DEFAULT_TOML,
                    help="config template whose picker list is rewritten in place")
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if the committed files differ from a fresh "
                         "generation (CI drift gate); skips if the submodule is absent")
    args = ap.parse_args()

    if not os.path.isdir(args.schemes_dir):
        # The submodule is only needed to (re)generate. Downstream apply and a
        # dev machine without it initialized should not be blocked.
        if args.check:
            print(f"schemes dir {args.schemes_dir} absent; skipping palette drift check")
            return 0
        raise SystemExit(
            f"schemes dir not found: {args.schemes_dir}\n"
            "add the submodule first: "
            "git submodule add https://github.com/tinted-theming/schemes vendor/tinted-schemes")

    entries = build(args.schemes_dir)
    yaml_text = emit_yaml(entries)
    block = emit_palettedefs(entries)
    toml_text = open(args.toml, encoding="utf-8").read()
    new_toml = rewrite_markers(toml_text, block)

    if args.check:
        drift = []
        if open(args.out, encoding="utf-8").read() != yaml_text:
            drift.append(args.out)
        if toml_text != new_toml:
            drift.append(args.toml)
        if drift:
            print("palette drift in: " + ", ".join(drift), file=sys.stderr)
            print("run: python3 scripts/build-palettes.py", file=sys.stderr)
            return 1
        print("palettes up to date")
        return 0

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(yaml_text)
    with open(args.toml, "w", encoding="utf-8") as fh:
        fh.write(new_toml)
    print(f"wrote {len(entries)} schemes to {os.path.relpath(args.out, REPO)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
