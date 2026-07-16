#!/usr/bin/env bats
# tests/test_render_modify_shim.bats
# The standalone installer (scripts/install-notify.sh) has no chezmoi to render
# the modify_*.tmpl gate blocks, so it ships its own render_modify(): a regex
# line-parser that resolves the ai gates for the notify path (claude_hooks +
# codex_hooks ON, statusline OFF). This suite guards that shim against silently
# diverging from chezmoi's own rendering. For that gate combo it renders each
# modify_ template BOTH ways, runs the two rendered merge scripts on the same
# input, and asserts the merged results are identical.
#
# Functional (not byte) diff on purpose: chezmoi leaves a blank line where a
# `{{ if }}` / `{{ end }}` marker was and the shim drops the line entirely, so the
# two rendered scripts differ in whitespace but must MERGE identically.

CHEZMOI_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

  # Extract render_modify() from the installer (its header line down to the first
  # line that is exactly "}") and source it. Fail loudly if the grab is empty, so
  # a renamed / reshaped function can never make this suite silently pass.
  RM_SRC="${BATS_TMPDIR}/render_modify-$$.sh"
  awk '/^render_modify\(\) \{/{f=1} f{print} /^\}$/{if(f)exit}' \
    "${CHEZMOI_DIR}/scripts/install-notify.sh" > "$RM_SRC"
  grep -q '^render_modify() {' "$RM_SRC" \
    || { echo "could not extract render_modify from install-notify.sh"; return 1; }
  # shellcheck source=/dev/null
  source "$RM_SRC"

  # Gate config matching the shim's hardcoded GATES (hooks on, statusline off).
  CZ_CFG="${BATS_TMPDIR}/cz-cfg-$$.toml"
  printf '[data]\n[data.components.ai]\nclaude_hooks = true\ncodex_hooks = true\nstatusline = false\n' \
    > "$CZ_CFG"
}

teardown() {
  rm -f "$RM_SRC" "$CZ_CFG"
}

# Render $1 (a modify_ template) via the shim and via chezmoi, run each rendered
# script on $2 (a stdin fixture file), and assert the merged outputs match.
assert_shim_matches_chezmoi() {
  local tmpl="$1" input="$2"
  local shim_py cz_py shim_out cz_out
  shim_py="${BATS_TMPDIR}/shim-$$.py";  cz_py="${BATS_TMPDIR}/cz-$$.py"
  shim_out="${BATS_TMPDIR}/shim-$$.out"; cz_out="${BATS_TMPDIR}/cz-$$.out"

  render_modify "$tmpl" > "$shim_py" || { echo "shim render failed"; return 1; }
  chezmoi execute-template --config "$CZ_CFG" < "$tmpl" > "$cz_py" \
    || { echo "chezmoi render failed"; return 1; }
  [ -s "$shim_py" ] || { echo "shim render produced no output"; return 1; }
  [ -s "$cz_py" ]   || { echo "chezmoi render produced no output"; return 1; }

  python3 "$shim_py" < "$input" > "$shim_out" || { echo "shim script failed to run"; return 1; }
  python3 "$cz_py"   < "$input" > "$cz_out"   || { echo "chezmoi script failed to run"; return 1; }

  diff "$shim_out" "$cz_out" || { echo "shim/chezmoi merged output diverged for $tmpl"; return 1; }
}

@test "render_modify matches chezmoi for settings.json (hooks on, statusline off)" {
  local input="${BATS_TMPDIR}/settings-in-$$.json"
  printf '{"model":"x","env":{"CLAUDE_CODE_DISABLE_MOUSE_CLICKS":"1","KEEP":"y"},"hooks":{}}\n' \
    > "$input"
  assert_shim_matches_chezmoi "${CHEZMOI_DIR}/dot_claude/modify_settings.json.tmpl" "$input"
}

@test "render_modify matches chezmoi for codex config.toml (hooks on, statusline off)" {
  local input="${BATS_TMPDIR}/codex-in-$$.toml"
  printf '[tui]\ntheme = "mine"\n[projects."/x"]\ntrust_level = "trusted"\n' > "$input"
  assert_shim_matches_chezmoi "${CHEZMOI_DIR}/dot_codex/modify_private_config.toml.tmpl" "$input"
}
