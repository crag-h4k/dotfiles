#!/usr/bin/env bats
# tests/test_opencode_talk.bats
# The opt-in voice plugin: a pinned opencode-talk checkout, three local patches, and a
# helper built from source. Nothing here records audio. The git, swiftc, codesign,
# uname, and sw_vers commands are PATH stubs, and the helper the stub "builds" would
# write a marker if anything ever ran it. gh must never be called.
#
# shellcheck disable=SC2030,SC2031
# Bats runs each @test in its own subshell, so an `export` scoped to one test never
# leaking into another is the intended behavior, not a bug.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
TALK_DIR="$REPO_ROOT/scripts/opencode-talk"
BUILD="$TALK_DIR/build.sh"
WRAPPER_TMPL="$REPO_ROOT/home/.chezmoiscripts/run_before_20-build-opencode-talk.sh.tmpl"
PATCHES=(
  0001-helper-on-device-only.patch
  0002-indicator-before-footer-status.patch
  0003-spoken-submit-send-it-only.patch
  0004-spoken-submit-needs-autosend.patch
)

setup() {
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/stubs"
  TREE="$BATS_TEST_TMPDIR/upstream"
  DEST="$TEST_HOME/.config/opencode/v2-plugins/talk"
  export STUB_LOG="$BATS_TEST_TMPDIR/calls.log"
  export STUB_TREE="$TREE"
  export EXEC_MARKER="$BATS_TEST_TMPDIR/helper-executed"
  mkdir -p "$TEST_HOME" "$STUBS" "$BATS_TEST_TMPDIR/tmp" "$TREE/helper" "$TREE/lib" "$TREE/test" "$TREE/docs" "$TREE/.github"
  : >"$STUB_LOG"
  PIN_SHA="$(sed -n 's/^PIN_SHA="\([0-9a-f]*\)"$/\1/p' "$BUILD")"
  export STUB_HEAD="$PIN_SHA"

  printf '// fake main.swift\n' >"$TREE/helper/main.swift"
  printf '<plist/>\n' >"$TREE/helper/Info.plist"
  printf '// fake tui.js\n' >"$TREE/tui.js"
  printf '// fake clean.js\n' >"$TREE/lib/clean.js"
  printf '{"name":"opencode-talk"}\n' >"$TREE/package.json"
  printf 'MIT fixture\n' >"$TREE/LICENSE"
  printf 'readme\n' >"$TREE/README.md"
  printf 'test\n' >"$TREE/test/x.test.js"
  printf 'doc\n' >"$TREE/docs/x.md"
  printf 'ci\n' >"$TREE/.github/ci.yml"

  # uname and sw_vers: darwin, arm64, macOS 26 unless a test overrides them.
  cat >"$STUBS/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${STUB_OS:-Darwin}" ;;
  -m) printf '%s\n' "${STUB_ARCH:-arm64}" ;;
  *) printf '%s\n' "${STUB_OS:-Darwin}" ;;
esac
EOF
  cat >"$STUBS/sw_vers" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${STUB_MACOS:-26.0.1}"
EOF
  # git: clone copies the fixture tree, rev-parse reports STUB_HEAD, and a patch named
  # in STUB_APPLY_FAIL fails its check. Every call is logged.
  cat >"$STUBS/git" <<'EOF'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$STUB_LOG"
case "${1:-}" in
  clone)
    dest="${*: -1}"
    mkdir -p "$dest"
    cp -R "$STUB_TREE/." "$dest"
    exit 0
    ;;
  -C)
    shift 2
    case "${1:-}" in
      checkout) exit 0 ;;
      rev-parse) printf '%s\n' "$STUB_HEAD"; exit 0 ;;
      apply)
        [ "$(basename "${*: -1}")" = "${STUB_APPLY_FAIL:-none}" ] && exit 1
        exit 0
        ;;
    esac
    ;;
esac
exit 0
EOF
  # swiftc: log the call, honor STUB_SWIFTC_FAIL, and write a helper that would leave a
  # marker if it were ever executed.
  cat >"$STUBS/swiftc" <<'EOF'
#!/usr/bin/env bash
printf 'swiftc %s\n' "$*" >>"$STUB_LOG"
[ -z "${STUB_SWIFTC_FAIL:-}" ] || exit 1
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then out="$2"; fi
  shift
done
mkdir -p "$(dirname "$out")"
printf '#!/bin/sh\ntouch "%s"\n' "$EXEC_MARKER" >"$out"
chmod +x "$out"
EOF
  cat >"$STUBS/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >>"$STUB_LOG"
[ -z "${STUB_CODESIGN_FAIL:-}" ] || exit 1
exit 0
EOF
  # gh is never needed to build; any call is a bug.
  cat >"$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$STUB_LOG"
exit 1
EOF
  chmod +x "$STUBS"/*
}

run_build() {
  run env HOME="$TEST_HOME" TMPDIR="$BATS_TEST_TMPDIR/tmp" PATH="$STUBS:$PATH" "$@" bash "$BUILD"
}

# A PATH holding the stubs minus one tool, plus the few real utilities the script uses.
path_without() {
  local skip="$1" restricted="$BATS_TEST_TMPDIR/restricted" tool
  mkdir -p "$restricted"
  for tool in "$STUBS"/*; do
    [ "$(basename "$tool")" = "$skip" ] || ln -sf "$tool" "$restricted/"
  done
  for tool in mkdir cp mv rm mktemp dirname basename chmod cat shasum; do
    ln -sf "$(command -v "$tool")" "$restricted/$tool"
  done
  # The stubs start with `#!/usr/bin/env bash`, so bash must be on the restricted PATH.
  ln -sf "$BASH" "$restricted/bash"
  printf '%s' "$restricted"
}

log_has() { grep -Fq -- "$1" "$STUB_LOG"; }
log_lacks() { ! grep -Fq -- "$1" "$STUB_LOG"; }

seed_previous_install() {
  mkdir -p "$DEST/bin"
  printf 'previous release\n' >"$DEST/tui.js"
  printf 'previous helper\n' >"$DEST/bin/opencode-talk-helper"
}

# --- the build --------------------------------------------------------------

@test "the pin is a full commit hash for the audited tag" {
  [[ "$PIN_SHA" =~ ^[0-9a-f]{40}$ ]]
  grep -Fxq 'PIN_TAG="v0.1.1"' "$BUILD"
}

@test "build clones the pinned commit, patches it, builds arm64 only, and installs the plugin" {
  run_build
  [ "$status" -eq 0 ]

  log_has 'git clone --quiet --no-checkout https://github.com/batuhansk/opencode-talk.git '
  log_has "checkout --quiet --detach $PIN_SHA"
  log_has 'rev-parse HEAD'

  local patch applied expected=""
  for patch in "${PATCHES[@]}"; do
    log_has "apply --check $TALK_DIR/$patch"
    log_has "apply $TALK_DIR/$patch"
    expected="$expected$patch $patch "
  done
  # Patches go on in file order, and a check precedes each apply.
  applied="$(grep -F ' apply ' "$STUB_LOG" | sed 's|.*/||' | tr '\n' ' ')"
  [ "$applied" = "$expected" ]

  log_has '-target arm64-apple-macos14'
  log_has '-swift-version 6'
  log_has 'helper/main.swift'
  log_has '-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker helper/Info.plist'
  log_lacks 'x86_64'
  log_lacks '-warnings-as-errors'
  log_has 'codesign --force --sign - --identifier dev.opencode-talk.helper'
  log_has 'codesign --verify --strict'
  [ "$(grep -c '^gh ' "$STUB_LOG")" -eq 0 ]

  [ -f "$DEST/tui.js" ]
  [ -f "$DEST/lib/clean.js" ]
  [ -f "$DEST/package.json" ]
  [ -f "$DEST/LICENSE" ]
  [ -x "$DEST/bin/opencode-talk-helper" ]
  [ "$(cat "$DEST/PINNED_COMMIT")" = "$PIN_SHA" ]
  [[ "$(cat "$DEST/.build-stamp")" =~ ^[0-9a-f]{64}$ ]]
  # Sources, tests, docs, and the prebuilt-binary workflow never reach the plugin dir.
  [ ! -e "$DEST/helper" ]
  [ ! -e "$DEST/README.md" ]
  [ ! -e "$DEST/test" ]
  [ ! -e "$DEST/docs" ]
  [ ! -e "$DEST/.github" ]
  [[ "$output" == *"check"* ]]
  [ ! -e "$EXEC_MARKER" ]
}

@test "the build never executes the helper it produces" {
  run_build
  [ "$status" -eq 0 ]
  [ ! -e "$EXEC_MARKER" ]
  log_lacks 'opencode-talk-helper check'
  log_lacks 'opencode-talk-helper listen'
}

@test "build replaces an older install and leaves no temporary directories behind" {
  seed_previous_install
  run_build
  [ "$status" -eq 0 ]
  [ "$(cat "$DEST/tui.js")" = '// fake tui.js' ]
  [ "$(ls -A "$TEST_HOME/.config/opencode/v2-plugins")" = talk ]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/tmp")" ]
}

@test "a checkout that is not the pinned commit stops the build and keeps the previous install" {
  seed_previous_install
  run_build STUB_HEAD=0000000000000000000000000000000000000000
  [ "$status" -ne 0 ]
  [[ "$output" == *"$PIN_SHA"* ]]
  log_lacks 'swiftc'
  [ "$(cat "$DEST/tui.js")" = 'previous release' ]
}

@test "a patch that does not apply stops the build before compiling" {
  seed_previous_install
  run_build STUB_APPLY_FAIL=0002-indicator-before-footer-status.patch
  [ "$status" -ne 0 ]
  [[ "$output" == *"0002-indicator-before-footer-status.patch"* ]]
  log_lacks 'swiftc'
  log_lacks "apply $TALK_DIR/0003-spoken-submit-send-it-only.patch"
  [ "$(cat "$DEST/tui.js")" = 'previous release' ]
}

@test "a failed compile keeps the previous install" {
  seed_previous_install
  run_build STUB_SWIFTC_FAIL=1
  [ "$status" -ne 0 ]
  [ "$(cat "$DEST/tui.js")" = 'previous release' ]
  [ "$(cat "$DEST/bin/opencode-talk-helper")" = 'previous helper' ]
}

@test "a failed signature check keeps the previous install" {
  seed_previous_install
  run_build STUB_CODESIGN_FAIL=1
  [ "$status" -ne 0 ]
  [ "$(cat "$DEST/tui.js")" = 'previous release' ]
}

@test "a missing swiftc is reported with the fix, before anything is cloned" {
  local restricted
  restricted="$(path_without swiftc)"
  run env HOME="$TEST_HOME" PATH="$restricted" "$BASH" "$BUILD"
  [ "$status" -ne 0 ]
  [[ "$output" == *"swiftc"* ]]
  [[ "$output" == *"Command Line Tools"* ]]
  log_lacks 'git clone'
}

@test "build skips quietly off macOS, off arm64, below macOS 26, and in configs-only mode" {
  run_build STUB_OS=Linux
  [ "$status" -eq 0 ]
  run_build STUB_ARCH=x86_64
  [ "$status" -eq 0 ]
  run_build STUB_MACOS=15.6
  [ "$status" -eq 0 ]
  [[ "$output" == *"macOS 26"* ]]
  run_build DOTFILES_INSTALL_MODE=configs
  [ "$status" -eq 0 ]
  [[ "$output" == *"configs-only"* ]]
  log_lacks 'git clone'
  [ ! -e "$DEST" ]
}

# --- retry on every apply: the stamp ------------------------------------------

STAMP_NAME=".build-stamp"

clone_count() { grep -c '^git clone' "$STUB_LOG" || true; }

# A private copy of the build directory, so a test can edit a patch, the script, or the
# pin without touching the repository. build.sh finds its patches next to itself.
copy_talk_dir() {
  TALK_COPY="$BATS_TEST_TMPDIR/talk-copy"
  mkdir -p "$TALK_COPY"
  cp -R "$TALK_DIR/." "$TALK_COPY/"
}

run_copy() {
  run env HOME="$TEST_HOME" TMPDIR="$BATS_TEST_TMPDIR/tmp" PATH="$STUBS:$PATH" "$@" bash "$TALK_COPY/build.sh"
}

@test "the first run builds and writes a stamp, and the next run changes nothing" {
  run_build
  [ "$status" -eq 0 ]
  [[ "$(cat "$DEST/$STAMP_NAME")" =~ ^[0-9a-f]{64}$ ]]
  [ "$(clone_count)" -eq 1 ]
  local stamp
  stamp="$(cat "$DEST/$STAMP_NAME")"

  run_build
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(clone_count)" -eq 1 ]
  [ "$(cat "$DEST/$STAMP_NAME")" = "$stamp" ]
}

@test "an up to date install needs no compiler, no git, and no network" {
  run_build
  [ "$status" -eq 0 ]
  local restricted
  restricted="$(path_without swiftc)"
  rm "$restricted/git"
  run env HOME="$TEST_HOME" PATH="$restricted" "$BASH" "$BUILD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(clone_count)" -eq 1 ]
}

@test "an edited patch, an edited script, or a new pin rebuilds" {
  copy_talk_dir
  run_copy
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 1 ]
  local before
  before="$(cat "$DEST/$STAMP_NAME")"

  printf '\n' >>"$TALK_COPY/0003-spoken-submit-send-it-only.patch"
  run_copy
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 2 ]
  [ "$(cat "$DEST/$STAMP_NAME")" != "$before" ]
  before="$(cat "$DEST/$STAMP_NAME")"

  printf '# edited\n' >>"$TALK_COPY/build.sh"
  run_copy
  [ "$(clone_count)" -eq 3 ]
  [ "$(cat "$DEST/$STAMP_NAME")" != "$before" ]
  before="$(cat "$DEST/$STAMP_NAME")"

  local newpin=1111111111111111111111111111111111111111
  sed -i.bak "s/^PIN_SHA=.*/PIN_SHA=\"$newpin\"/" "$TALK_COPY/build.sh"
  run_copy STUB_HEAD="$newpin"
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 4 ]
  [ "$(cat "$DEST/$STAMP_NAME")" != "$before" ]
  [ "$(cat "$DEST/PINNED_COMMIT")" = "$newpin" ]

  run_copy STUB_HEAD="$newpin"
  [ "$(clone_count)" -eq 4 ]
}

@test "a missing stamp, plugin entry file, or helper rebuilds" {
  run_build
  [ "$(clone_count)" -eq 1 ]

  rm "$DEST/bin/opencode-talk-helper"
  run_build
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 2 ]
  [ -x "$DEST/bin/opencode-talk-helper" ]

  rm "$DEST/tui.js"
  run_build
  [ "$(clone_count)" -eq 3 ]
  [ -f "$DEST/tui.js" ]

  rm "$DEST/$STAMP_NAME"
  run_build
  [ "$(clone_count)" -eq 4 ]
  [ -f "$DEST/$STAMP_NAME" ]

  run_build
  [ "$(clone_count)" -eq 4 ]
}

@test "an install from before the stamp existed is rebuilt once" {
  seed_previous_install
  run_build
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 1 ]
  [ -f "$DEST/$STAMP_NAME" ]
}

@test "a failed first build writes no stamp and the next run tries again" {
  run_build STUB_SWIFTC_FAIL=1
  [ "$status" -ne 0 ]
  [ ! -e "$DEST/$STAMP_NAME" ]
  [ "$(clone_count)" -eq 1 ]

  run_build
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 2 ]
  [ -f "$DEST/$STAMP_NAME" ]
}

@test "a failed rebuild keeps the old stamp, so the next apply retries" {
  copy_talk_dir
  run_copy
  local old
  old="$(cat "$DEST/$STAMP_NAME")"

  printf '\n' >>"$TALK_COPY/0001-helper-on-device-only.patch"
  run_copy STUB_SWIFTC_FAIL=1
  [ "$status" -ne 0 ]
  [ "$(cat "$DEST/$STAMP_NAME")" = "$old" ]
  [ "$(cat "$DEST/tui.js")" = '// fake tui.js' ]

  run_copy
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 3 ]
  [ "$(cat "$DEST/$STAMP_NAME")" != "$old" ]
}

@test "--force rebuilds an install that is up to date" {
  run_build
  [ "$(clone_count)" -eq 1 ]
  run env HOME="$TEST_HOME" TMPDIR="$BATS_TEST_TMPDIR/tmp" PATH="$STUBS:$PATH" bash "$BUILD" --force
  [ "$status" -eq 0 ]
  [ "$(clone_count)" -eq 2 ]
}

# --- the chezmoi script -------------------------------------------------------

render_wrapper() { # os, then data lines for [data.components.ai]
  local os="$1" ai="$2" config="$BATS_TEST_TMPDIR/chezmoi.toml"
  printf '[data]\ninstallMode = "packages"\n[data.components.ai]\n%b' "$ai" >"$config"
  chezmoi execute-template --source "$REPO_ROOT" --config "$config" \
    --override-data "{\"chezmoi\":{\"os\":\"$os\"}}" <"$WRAPPER_TMPL"
}

@test "the chezmoi script renders nothing unless voice, OpenCode, and macOS are all selected" {
  local out
  out="$(render_wrapper darwin 'opencode = true\n')"
  [ -z "${out//[[:space:]]/}" ]
  out="$(render_wrapper darwin 'opencode = true\nvoice = false\n')"
  [ -z "${out//[[:space:]]/}" ]
  out="$(render_wrapper darwin 'opencode = false\nvoice = true\n')"
  [ -z "${out//[[:space:]]/}" ]
  out="$(render_wrapper linux 'opencode = true\nvoice = true\n')"
  [ -z "${out//[[:space:]]/}" ]
  out="$(render_wrapper darwin 'opencode = true\nvoice = true\n')"
  [[ "$out" == '#!/usr/bin/env bash'* ]]
  [[ "$out" == *"$TALK_DIR/build.sh"* ]]
}

@test "it is a plain before script, so chezmoi runs it on every apply" {
  [ -f "$WRAPPER_TMPL" ]
  [[ "$(basename "$WRAPPER_TMPL")" == run_before_* ]]
  [[ "$(basename "$WRAPPER_TMPL")" != *onchange* ]]
  [ ! -e "$REPO_ROOT/home/.chezmoiscripts/run_onchange_before_20-build-opencode-talk.sh.tmpl" ]
}

@test "the rendered script is valid bash and warns instead of failing the apply" {
  local out
  out="$(render_wrapper darwin 'opencode = true\nvoice = true\n')"
  printf '%s\n' "$out" >"$BATS_TEST_TMPDIR/rendered.sh"
  bash -n "$BATS_TEST_TMPDIR/rendered.sh"
  grep -Fq 'WARNING' "$BATS_TEST_TMPDIR/rendered.sh"
  [[ "$out" == *'export DOTFILES_INSTALL_MODE="packages"'* ]]

  run env HOME="$TEST_HOME" PATH="$STUBS:$PATH" STUB_SWIFTC_FAIL=1 bash "$BATS_TEST_TMPDIR/rendered.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
  [[ "$output" == *"build.sh"* ]]
  log_has 'swiftc'
  [ ! -e "$DEST/$STAMP_NAME" ]
}

@test "the rendered script builds once and then stays out of the way" {
  local out
  out="$(render_wrapper darwin 'opencode = true\nvoice = true\n')"
  printf '%s\n' "$out" >"$BATS_TEST_TMPDIR/rendered.sh"
  run env HOME="$TEST_HOME" PATH="$STUBS:$PATH" bash "$BATS_TEST_TMPDIR/rendered.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING"* ]]
  [ -x "$DEST/bin/opencode-talk-helper" ]
  [ "$(clone_count)" -eq 1 ]

  run env HOME="$TEST_HOME" PATH="$STUBS:$PATH" bash "$BATS_TEST_TMPDIR/rendered.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(clone_count)" -eq 1 ]
}

# --- the patches ------------------------------------------------------------

patch_has() { grep -Fxq -- "$2" "$TALK_DIR/$1"; }

@test "the patch set is exactly the four expected files, in build order" {
  local found="" file patch
  for file in "$TALK_DIR"/*.patch; do
    found="$found$(basename "$file") "
  done
  [ "$found" = "${PATCHES[*]} " ]
  for patch in "${PATCHES[@]}"; do
    grep -Fxq "    $patch" "$BUILD"
  done
}

@test "every patch is a well formed diff" {
  local patch
  for patch in "${PATCHES[@]}"; do
    run git apply --stat "$TALK_DIR/$patch"
    [ "$status" -eq 0 ]
  done
}

@test "helper patch ignores --allow-cloud and fails closed on cloud recognition" {
  local p=0001-helper-on-device-only.patch
  patch_has "$p" '-        allowCloud = true'
  patch_has "$p" '-    request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition'
  patch_has "$p" '+    request.requiresOnDeviceRecognition = true'
  patch_has "$p" '-  if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }'
  patch_has "$p" '+  request.requiresOnDeviceRecognition = true'
  patch_has "$p" '-func chooseEngine(_ requested: String, language: String, allowCloud: Bool) async -> (EngineKind, Locale?) {'
  patch_has "$p" '+func chooseEngine(_ requested: String, language: String, allowCloud _: Bool) async -> (EngineKind, Locale?) {'
  patch_has "$p" '+  let allowCloud = false'
  patch_has "$p" '-  let (engine, _) = await chooseEngine("auto", language: options.language, allowCloud: true)'
  patch_has "$p" '+  let (engine, _) = await chooseEngine("auto", language: options.language, allowCloud: false)'
  # No added line may turn cloud recognition back on.
  run grep -E '^\+.*(allowCloud = true|allowCloud: true|supportsOnDeviceRecognition)' "$TALK_DIR/$p"
  [ "$status" -ne 0 ]
}

@test "indicator patch claims a slot beside the footer status, not inside the replaced one" {
  local p=0002-indicator-before-footer-status.patch
  patch_has "$p" '-    prepend: "prompt.footer.status",'
  patch_has "$p" '+    before: "prompt.footer.status",'
}

@test "spoken submit patch accepts only the phrase send it" {
  local p=0003-spoken-submit-send-it-only.patch
  patch_has "$p" '-  en: /[\s,.]*\b(send it|send|submit)[.!]?$/i,'
  patch_has "$p" '+  en: /[\s,.]*\b(send it)[.!]?$/i,'
}

@test "autoSend patch strips and acts on a spoken send it only when autoSend is on" {
  local p=0004-spoken-submit-needs-autosend.patch
  patch_has "$p" '-          const { text, send } = extractSend(clean(raw, vocab, language?.lang), language?.lang)'
  patch_has "$p" '-          const submit = send || settings.get("autoSend") === true'
  patch_has "$p" '+          const autoSend = settings.get("autoSend") === true'
  patch_has "$p" '+          const cleaned = clean(raw, vocab, language?.lang)'
  patch_has "$p" '+          const { text, send } = autoSend ? extractSend(cleaned, language?.lang) : { text: cleaned, send: false }'
  patch_has "$p" '+          const submit = send || autoSend'
}

# Run the lines the autoSend patch adds, with stand-ins for clean and extractSend, so the
# decision (insert verbatim, or strip and submit) is exercised without the host modules.
decide() { # autoSend raw
  node -e '
    const fs = require("fs")
    const added = fs.readFileSync(process.argv[1], "utf8").split("\n")
      .filter((l) => l.startsWith("+") && !l.startsWith("+++")).map((l) => l.slice(1)).join("\n")
    const clean = (raw) => raw
    const extractSend = (t) => (/ send it$/.test(t) ? { text: t.replace(/ send it$/, ""), send: true } : { text: t, send: false })
    const settings = { get: (k) => (k === "autoSend" ? JSON.parse(process.argv[2]) : undefined) }
    const decide = new Function("clean", "extractSend", "settings", "raw", "vocab", "language", added + "\nreturn { text, send, submit }")
    process.stdout.write(JSON.stringify(decide(clean, extractSend, settings, process.argv[3], {}, "en")))
  ' "$TALK_DIR/0004-spoken-submit-needs-autosend.patch" "$1" "$2"
}

@test "with autoSend off, a spoken send it stays in the prompt and nothing submits" {
  command -v node >/dev/null || skip "node is needed to run the patched decision"
  run decide false "run the tests send it"
  [ "$status" -eq 0 ]
  [ "$output" = '{"text":"run the tests send it","send":false,"submit":false}' ]
  run decide false "run the tests"
  [ "$output" = '{"text":"run the tests","send":false,"submit":false}' ]
}

@test "with autoSend on, a spoken send it is stripped and the prompt submits" {
  command -v node >/dev/null || skip "node is needed to run the patched decision"
  run decide true "run the tests send it"
  [ "$status" -eq 0 ]
  [ "$output" = '{"text":"run the tests","send":true,"submit":true}' ]
  run decide true "run the tests"
  [ "$output" = '{"text":"run the tests","send":false,"submit":true}' ]
}

@test "anything but a literal true leaves autoSend off" {
  command -v node >/dev/null || skip "node is needed to run the patched decision"
  run decide '"true"' "run the tests send it"
  [ "$output" = '{"text":"run the tests send it","send":false,"submit":false}' ]
  run decide null "run the tests send it"
  [ "$output" = '{"text":"run the tests send it","send":false,"submit":false}' ]
}

@test "patches apply to the pinned source when a checkout is provided" {
  if [ -z "${OPENCODE_TALK_SOURCE:-}" ]; then
    skip "set OPENCODE_TALK_SOURCE to a tree at the pinned commit to check the patches against it"
  fi
  local copy="$BATS_TEST_TMPDIR/pinned" patch
  mkdir -p "$copy"
  cp -R "$OPENCODE_TALK_SOURCE/." "$copy"
  for patch in "${PATCHES[@]}"; do
    run git -C "$copy" apply --check "$TALK_DIR/$patch"
    [ "$status" -eq 0 ]
  done
  # Applied together, the patches still compose.
  for patch in "${PATCHES[@]}"; do
    git -C "$copy" apply "$TALK_DIR/$patch"
  done
  if command -v node >/dev/null; then
    for patch in "$copy"/tui.js "$copy"/lib/*.js; do node --check "$patch"; done
  fi
}

@test "on the patched source, spoken send it follows autoSend through the real clean and extractSend" {
  if [ -z "${OPENCODE_TALK_SOURCE:-}" ]; then
    skip "set OPENCODE_TALK_SOURCE to a tree at the pinned commit to run the patched source"
  fi
  command -v node >/dev/null || skip "node is needed to run the patched source"
  local copy="$BATS_TEST_TMPDIR/pinned" patch
  mkdir -p "$copy"
  cp -R "$OPENCODE_TALK_SOURCE/." "$copy"
  for patch in "${PATCHES[@]}"; do
    git -C "$copy" apply "$TALK_DIR/$patch"
  done
  run node --input-type=module -e '
    import { readFileSync } from "node:fs"
    import { pathToFileURL } from "node:url"
    import assert from "node:assert/strict"
    const root = process.argv[1]
    const { buildVocab, clean, extractSend } = await import(pathToFileURL(root + "/lib/clean.js"))
    const source = readFileSync(root + "/tui.js", "utf8").split("\n")
    const from = source.findIndex((l) => l.includes("const autoSend = "))
    const to = source.findIndex((l) => l.includes("const submit = "))
    assert.ok(from > 0 && to > from, "patched lines not found")
    const body = source.slice(from, to + 1).join("\n")
    const vocab = buildVocab()
    const decide = (auto, raw) => new Function("clean", "extractSend", "settings", "raw", "vocab", "language", body + "\nreturn { text, submit }")(
      clean, extractSend, { get: () => auto }, raw, vocab, "en")
    assert.deepEqual(decide(false, "fix the bug and send it"), { text: "Fix the bug and send it", submit: false })
    assert.deepEqual(decide(true, "fix the bug and send it"), { text: "Fix the bug and", submit: true })
    assert.deepEqual(decide(true, "please send"), { text: "Please send", submit: true })
    assert.deepEqual(decide(false, "please send"), { text: "Please send", submit: false })
  ' "$copy"
  [ "$status" -eq 0 ]
}
