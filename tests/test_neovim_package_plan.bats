#!/usr/bin/env bats
# Native metadata inspection and exact-version application in an isolated home.
# shellcheck source-path=SCRIPTDIR
# Bats intentionally isolates each test in a subshell.
# shellcheck disable=SC2030,SC2031
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup() {
  # Commit hooks export a temporary index; fixture repositories must use their own.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_INDEX_VERSION GIT_CONFIG_PARAMETERS
  command -v nvim >/dev/null || skip "Neovim unavailable"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.data"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.state"
  export DOTFILES_SOURCE_ROOT="$BATS_TEST_TMPDIR/source"
  export TEST_PLUGIN="$XDG_DATA_HOME/nvim/lazy/nvim-treesitter"
  export TEST_NATIVE_LOG="$BATS_TEST_TMPDIR/native.log"
  local lazy="$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy"
  local mason="$XDG_DATA_HOME/nvim/lazy/mason.nvim/lua"
  mkdir -p "$lazy/core" "$lazy/manage" "$mason/mason" "$DOTFILES_SOURCE_ROOT/home/dot_config/nvim" \
    "$XDG_CONFIG_HOME/nvim" "$TEST_PLUGIN/lua/nvim-treesitter" "$XDG_DATA_HOME/nvim/site/parser-info" \
    "$XDG_DATA_HOME/nvim/site/parser"
  printf 'return {}\n' >"$lazy/init.lua"
  printf 'return {lock={}}\n' >"$lazy/manage/lock.lua"
  cat >"$DOTFILES_SOURCE_ROOT/home/dot_config/nvim/init.lua" <<'LUA'
return { plugins = {}, parsers = { "lua" }, lsp_servers = { "pyright" } }
LUA
  cat >"$lazy/core/config.lua" <<'LUA'
local M = { plugins = {} }
function M.setup(options)
  options.lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  M.options = options
end
return M
LUA
  cat >"$lazy/core/plugin.lua" <<'LUA'
return { load = function()
  require("lazy.core.config").plugins = {
    ["nvim-treesitter"] = { dir = vim.env.TEST_PLUGIN, url = vim.env.TEST_PLUGIN, _ = { installed = true } },
  }
end }
LUA
  cat >"$lazy/manage/git.lua" <<'LUA'
return {
  info = function(directory)
    return { commit = vim.trim(vim.system({ "git", "-C", directory, "rev-parse", "HEAD" }, { text = true }):wait().stdout) }
  end,
  get_target = function() return { commit = vim.env.TEST_CANDIDATE } end,
}
LUA
  cat >"$lazy/manage/init.lua" <<'LUA'
return {
  check = function() end,
  install = function() error("unapproved plugin installation") end,
  update = function(options)
    assert(options.lockfile, "update did not use approved lockfile")
    local config = require("lazy.core.config")
    local lock = vim.json.decode(table.concat(vim.fn.readfile(config.options.lockfile), "\n"))
    for _, name in ipairs(options.plugins) do
      local result = vim.system({ "git", "-C", config.plugins[name].dir, "checkout", "--detach", lock[name].commit }):wait()
      assert(result.code == 0)
    end
  end,
}
LUA
  printf 'return { setup = function() end }\n' >"$mason/mason/init.lua"
  cat >"$mason/mason-registry.lua" <<'LUA'
local versions = { gitleaks = "1", pyright = nil }
return {
  update = function(callback) callback(vim.env.TEST_REGISTRY_FAIL ~= "1") end,
  get_installed_package_names = function() return { "gitleaks" } end,
  get_all_package_specs = function() return {{ name = "pyright", neovim = { lspconfig = "pyright" } }} end,
  get_package = function(name)
    return {
      get_installed_version = function() return versions[name] end,
      get_latest_version = function() return name == "gitleaks" and "1" or "99" end,
      install = function(_, options, callback)
        assert(options.version, "Mason install was not pinned")
        local log = assert(io.open(vim.env.TEST_NATIVE_LOG, "a"))
        log:write(name .. "=" .. options.version .. "\n")
        log:close()
        versions[name] = options.version
        callback(true)
      end,
    }
  end,
}
LUA
  git -C "$TEST_PLUGIN" init -q
  git -C "$TEST_PLUGIN" config user.name Fixture
  git -C "$TEST_PLUGIN" config user.email fixture@example.invalid
  printf 'return {lua={install_info={revision="old-parser",url="https://example.invalid/lua"}}}\n' >"$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua"
  git -C "$TEST_PLUGIN" add .
  git -C "$TEST_PLUGIN" commit -qm old
  export TEST_CURRENT
  TEST_CURRENT=$(git -C "$TEST_PLUGIN" rev-parse HEAD)
  printf 'return {lua={install_info={revision="new-parser",url="https://example.invalid/lua"}}}\n' >"$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua"
  git -C "$TEST_PLUGIN" commit -qam candidate
  export TEST_CANDIDATE
  TEST_CANDIDATE=$(git -C "$TEST_PLUGIN" rev-parse HEAD)
  git -C "$TEST_PLUGIN" checkout -q --detach "$TEST_CURRENT"
  git -C "$TEST_PLUGIN" remote add origin "$TEST_PLUGIN"
  printf 'old-parser\n' >"$XDG_DATA_HOME/nvim/site/parser-info/lua.revision"
  : >"$XDG_DATA_HOME/nvim/site/parser/lua.so"
}

@test "native plan expands candidates and configured missing packages without installing" {
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'neovim-plugin\tnvim-treesitter\tupdate'* ]]
  [[ "$output" == *$'treesitter-parsers\tlua\tupdate'* ]]
  [[ "$output" == *$'old-parser\tnew-parser\t'* ]]
  [[ "$output" == *$'mason-packages\tpyright\tplanned'* ]]
  [[ "$output" == *$'mason-packages\tgitleaks\tinstalled'* ]]
  [ "$(git -C "$TEST_PLUGIN" rev-parse HEAD)" = "$TEST_CURRENT" ]
  [ "$(cat "$XDG_DATA_HOME/nvim/site/parser-info/lua.revision")" = old-parser ]
  [ ! -e "$TEST_NATIVE_LOG" ]
}

@test "a missing parser binary is planned even with a matching revision receipt" {
  printf 'new-parser\n' >"$XDG_DATA_HOME/nvim/site/parser-info/lua.revision"
  rm "$XDG_DATA_HOME/nvim/site/parser/lua.so"
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'treesitter-parsers\tlua\tplanned'* ]]
}

@test "failed registry metadata is blocked instead of current" {
  run env TEST_REGISTRY_FAIL=1 nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'mason-packages\tconfigured Mason package set\tblocked'* ]]
}

@test "Mason applies the approved version when the registry offers a newer one" {
  local plan="$BATS_TEST_TMPDIR/approved.tsv"
  printf 'mason-packages\tpyright\tplanned\tfloating\tmason-registry\t-\t-\t2\tapproved\n' >"$plan"
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_NATIVE_LOG")" = pyright=2 ]
}

@test "Lazy applies the approved commit even after its candidate advances" {
  local plan="$BATS_TEST_TMPDIR/approved.tsv" approved="$TEST_CANDIDATE"
  printf 'neovim-plugin\tnvim-treesitter\tupdate\tfloating\t%s\t%s\t%s\t%s\tapproved\n' \
    "$TEST_PLUGIN" "$TEST_PLUGIN" "$TEST_CURRENT" "$approved" >"$plan"
  export TEST_CANDIDATE=0000000000000000000000000000000000000000
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_PLUGIN" rev-parse HEAD)" = "$approved" ]
}

@test "current native records do not load plugins or install artifacts" {
  local plan="$BATS_TEST_TMPDIR/current.tsv"
  printf 'mason-packages\tgitleaks\tinstalled\tfloating\tmason-registry\t-\t1\t1\tcurrent\n' >"$plan"
  printf 'error("user plugins must not load")\n' >"$DOTFILES_SOURCE_ROOT/home/dot_config/nvim/init.lua"
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_NATIVE_LOG" ]
}

@test "planner preserves and blocks staged and untracked plugin edits" {
  printf '\n-- user edit\n' >>"$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua"
  git -C "$TEST_PLUGIN" add .
  printf 'local note\n' >"$TEST_PLUGIN/user-note"
  local before
  before=$(sha256sum "$TEST_PLUGIN/.git/index" "$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua" "$TEST_PLUGIN/user-note")
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'neovim-plugin\tnvim-treesitter\tblocked'* ]]
  [ "$(sha256sum "$TEST_PLUGIN/.git/index" "$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua" "$TEST_PLUGIN/user-note")" = "$before" ]
}

@test "Lazy refuses origin drift after approval without removing user files" {
  local plan="$BATS_TEST_TMPDIR/origin.tsv"
  printf 'neovim-plugin\tnvim-treesitter\tupdate\tfloating\t%s\t%s\t%s\t%s\tapproved\n' \
    "$TEST_PLUGIN" "$TEST_PLUGIN" "$TEST_CURRENT" "$TEST_CANDIDATE" >"$plan"
  git -C "$TEST_PLUGIN" remote set-url origin https://example.invalid/changed
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -ne 0 ]
  [[ "$output" == *'plugin origin changed'* ]]
  [ "$(git -C "$TEST_PLUGIN" rev-parse HEAD)" = "$TEST_CURRENT" ]
}

@test "missing parser binary repair uses the approved revision and verifies the artifact" {
  local plan="$BATS_TEST_TMPDIR/parser.tsv"
  rm "$XDG_DATA_HOME/nvim/site/parser/lua.so"
  printf 'treesitter-parsers\tlua\tplanned\tfloating\tfixture\t%s\t-\told-parser\tmissing binary\n' \
    "$XDG_DATA_HOME/nvim/site/parser-info/lua.revision" >"$plan"
  printf 'neovim-plugin\tnvim-treesitter\tinstalled\tfloating\t%s\t%s\t%s\t%s\tcurrent\n' \
    "$TEST_PLUGIN" "$TEST_PLUGIN" "$TEST_CURRENT" "$TEST_CURRENT" >>"$plan"
  printf 'return {norm_languages=function(names) return names end}\n' >"$TEST_PLUGIN/lua/nvim-treesitter/config.lua"
  cat >"$TEST_PLUGIN/lua/nvim-treesitter/init.lua" <<'LUA'
return {
  setup = function() end,
  install = function(names)
    assert(#names == 1 and names[1] == "lua")
    vim.fn.writefile({}, vim.fn.stdpath("data") .. "/site/parser/lua.so")
    return { wait = function() return true end }
  end,
}
LUA
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -eq 0 ]
  [ -f "$XDG_DATA_HOME/nvim/site/parser/lua.so" ]
}

@test "Lazy freezes targets again between missing-plugin installation and existing-plugin update" {
  local lazy="$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy" plan="$BATS_TEST_TMPDIR/mixed.tsv"
  export TEST_EXTRA="$XDG_DATA_HOME/nvim/lazy/extra"
  python3 - "$lazy/core/plugin.lua" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); s=p.read_text()
s=s.replace('  }\nend }', '''    extra = { name = "extra", dir = vim.env.TEST_EXTRA, url = "fixture", _ = { installed = false } },
  }
end }''')
p.write_text(s)
PY
  cat >"$lazy/manage/init.lua" <<'LUA'
local config = require("lazy.core.config")
local state = require("lazy.manage.lock")
return {
  install = function()
    config.plugins.extra._.installed = true
    -- Lazy's lock.update replaces cached and on-disk entries with installed HEADs.
    state.lock["nvim-treesitter"].commit = vim.env.TEST_CURRENT
    vim.fn.writefile({vim.json.encode(state.lock)}, config.options.lockfile)
  end,
  update = function(options)
    assert(options.lockfile)
    assert(state.lock["nvim-treesitter"].commit == vim.env.TEST_CANDIDATE, "install phase overwrote the approved update")
    local result = vim.system({"git", "-C", vim.env.TEST_PLUGIN, "checkout", "--detach", state.lock["nvim-treesitter"].commit}):wait()
    assert(result.code == 0)
  end,
}
LUA
  cat >"$lazy/manage/git.lua" <<'LUA'
return {
  info = function(directory)
    if directory == vim.env.TEST_EXTRA then
      if require("lazy.core.config").plugins.extra._.installed then return {commit=vim.env.TEST_CANDIDATE} end
      return nil
    end
    return {commit=vim.trim(vim.system({"git","-C",directory,"rev-parse","HEAD"},{text=true}):wait().stdout)}
  end,
}
LUA
  printf 'neovim-plugin\textra\tplanned\tfloating\tfixture\t%s\t-\t%s\tmissing\n' "$TEST_EXTRA" "$TEST_CANDIDATE" >"$plan"
  printf 'neovim-plugin\tnvim-treesitter\tupdate\tfloating\t%s\t%s\t%s\t%s\tupdate\n' \
    "$TEST_PLUGIN" "$TEST_PLUGIN" "$TEST_CURRENT" "$TEST_CANDIDATE" >>"$plan"
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/update-neovim-packages.lua" "$plan"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_PLUGIN" rev-parse HEAD)" = "$TEST_CANDIDATE" ]
}

@test "a current dependency is explicitly planned for the native parser rebuild" {
  git -C "$TEST_PLUGIN" checkout -q --detach "$TEST_CANDIDATE"
  cat >"$TEST_PLUGIN/lua/nvim-treesitter/parsers.lua" <<'LUA'
return {
  lua = { install_info = { revision = "new-parser", url = "fixture" }, requires = { "dependency" } },
  dependency = { install_info = { revision = "same-parser", url = "fixture" } },
}
LUA
  git -C "$TEST_PLUGIN" commit -qam dependency
  export TEST_CANDIDATE
  TEST_CANDIDATE=$(git -C "$TEST_PLUGIN" rev-parse HEAD)
  git -C "$TEST_PLUGIN" checkout -q --detach "$TEST_CURRENT"
  printf 'same-parser\n' >"$XDG_DATA_HOME/nvim/site/parser-info/dependency.revision"
  : >"$XDG_DATA_HOME/nvim/site/parser/dependency.so"
  run nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'treesitter-parsers\tdependency\tupdate'* ]]
  [[ "$output" == *$'same-parser\tsame-parser\trebuilt by lua installation'* ]]
}

@test "fresh manager bootstrap resolves another plan before native installation" {
  local stubs="$BATS_TEST_TMPDIR/stubs" plan="$BATS_TEST_TMPDIR/bootstrap.tsv"
  local root="$XDG_DATA_HOME/nvim/lazy/lazy.nvim" log="$BATS_TEST_TMPDIR/bootstrap.log"
  mkdir -p "$stubs"
  rm "$root/lua/lazy/init.lua"
  printf 'neovim-plugin\tlazy.nvim\tcheck\tfloating\tfixture\t%s\t-\t%s\tbootstrap\n' "$root" "$TEST_CANDIDATE" >"$plan"
  cat >"$stubs/nvim" <<'STUB'
#!/bin/sh
case "$*" in
  *plan-neovim-packages.lua*) printf 'mason-packages\tpyright\tplanned\tfloating\tmason-registry\t-\t-\t2\tresolved after bootstrap\n' ;;
  *update-neovim-packages.lua*) printf 'apply\n' >>"$TEST_BOOTSTRAP_LOG" ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$stubs/nvim"
  # The positional arguments are expanded by the child shell.
  # shellcheck disable=SC2016
  run env PATH="$stubs:$PATH" DOTFILES_PACKAGE_PLAN="$plan" DOTFILES_ASSUME_YES=1 \
    TEST_BOOTSTRAP_LOG="$log" bash -c '
      source "$1"
      bootstrap_lazy() { mkdir -p "$1/lua/lazy"; : >"$1/lua/lazy/init.lua"; }
      update_neovim_native_packages
    ' _ "$REPO_ROOT/scripts/install-neovim.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *pyright* ]]
  [ "$(cat "$log")" = apply ]
}

@test "prior top-level approval does not approve newly resolved bootstrap packages" {
  local stubs="$BATS_TEST_TMPDIR/stubs" plan="$BATS_TEST_TMPDIR/bootstrap.tsv"
  local root="$XDG_DATA_HOME/nvim/lazy/lazy.nvim" log="$BATS_TEST_TMPDIR/bootstrap.log"
  mkdir -p "$stubs"
  rm "$root/lua/lazy/init.lua"
  printf 'neovim-plugin\tlazy.nvim\tcheck\tfloating\tfixture\t%s\t-\t%s\tbootstrap\n' "$root" "$TEST_CANDIDATE" >"$plan"
  cat >"$stubs/nvim" <<'STUB'
#!/bin/sh
case "$*" in
  *plan-neovim-packages.lua*) printf 'mason-packages\tpyright\tplanned\tfloating\tmason-registry\t-\t-\t2\tresolved after bootstrap\n' ;;
  *) printf 'unapproved apply\n' >>"$TEST_BOOTSTRAP_LOG" ;;
esac
STUB
  chmod +x "$stubs/nvim"
  # The positional arguments are expanded by the child shell.
  # shellcheck disable=SC2016
  run env PATH="$stubs:$PATH" DOTFILES_PACKAGE_PLAN="$plan" DOTFILES_ASSUME_YES=0 \
    DOTFILES_PACKAGES_APPROVED=1 DOTFILES_TTY="$BATS_TEST_TMPDIR/no-tty" TEST_BOOTSTRAP_LOG="$log" \
    bash -c '
      source "$1"
      bootstrap_lazy() { mkdir -p "$1/lua/lazy"; : >"$1/lua/lazy/init.lua"; }
      update_neovim_native_packages
    ' _ "$REPO_ROOT/scripts/install-neovim.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$log" ]
}

@test "fresh Lazy bootstrap resolves the commit behind its annotated stable tag" {
  local stubs="$BATS_TEST_TMPDIR/bootstrap-git"
  mkdir -p "$stubs"
  rm "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
  cat >"$stubs/git" <<'STUB'
#!/bin/sh
[ "$1" = ls-remote ] || exit 1
printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\trefs/tags/stable\n'
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\trefs/tags/stable^{}\n'
STUB
  chmod +x "$stubs/git"
  run env PATH="$stubs:$PATH" nvim --headless -u NONE -i NONE -n -l "$REPO_ROOT/scripts/plan-neovim-packages.lua"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'neovim-plugin\tlazy.nvim\tcheck'* ]]
  [[ "$output" == *$'\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t'* ]]
  [[ "$output" != *aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa* ]]
}
