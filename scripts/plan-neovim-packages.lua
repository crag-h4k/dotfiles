-- Inspect metadata without loading user plugins or installing packages.
local source = debug.getinfo(1, "S").source:sub(2)
local lib = dofile(vim.fs.dirname(source) .. "/neovim-package-lib.lua")
local emit = lib.emit
local lazy_dir = lib.lazy_root .. "/lazy.nvim"

if not vim.uv.fs_stat(lazy_dir .. "/lua/lazy/init.lua") then
  local ok, output =
    pcall(lib.command, { "git", "ls-remote", "https://github.com/folke/lazy.nvim.git", "refs/heads/stable", "refs/tags/stable", "refs/tags/stable^{}" })
  local refs = {}
  if ok then
    for line in output:gmatch("[^\r\n]+") do
      local commit, ref = line:match("^(%x+)%s+(.+)$")
      if commit then
        refs[ref] = commit
      end
    end
  end
  local target = refs["refs/heads/stable"] or refs["refs/tags/stable^{}"] or refs["refs/tags/stable"]
  emit(
    "neovim-plugin",
    "lazy.nvim",
    target and "check" or "blocked",
    "https://github.com/folke/lazy.nvim.git",
    lazy_dir,
    nil,
    target,
    target and "bootstrap manager; display and confirm plugin plan afterwards" or "could not resolve Lazy bootstrap"
  )
  return
end

local spec = lib.spec()
local config = lib.lazy(spec)
local git = require("lazy.manage.git")
local targets = {}
for _, name in ipairs(lib.keys(config.plugins)) do
  local plugin = config.plugins[name]
  local info = git.info(plugin.dir)
  local current = info and info.commit
  local ok, candidate = pcall(function()
    if plugin._.is_local or plugin.pin then
      return assert(current, "local or pinned plugin is missing")
    elseif plugin._.installed then
      lib.clean_plugin(plugin.dir, plugin.url)
      assert(not plugin.version and not plugin.tag, "version-constrained plugin metadata is unsupported")
      local args =
        { "git", "-C", plugin.dir, "fetch", "--quiet", "--no-write-fetch-head", "--no-tags", "--no-auto-maintenance", "--recurse-submodules=no", "origin" }
      if plugin.branch then
        args[#args + 1] = "refs/heads/" .. plugin.branch .. ":refs/remotes/origin/" .. plugin.branch
      end
      lib.command(args)
      return assert(git.get_target(plugin).commit, "plugin target is unavailable")
    else
      assert(not plugin.version, "missing version-constrained plugin requires metadata")
      local ref = plugin.commit or (plugin.tag and ("refs/tags/" .. plugin.tag .. "^{}")) or (plugin.branch and ("refs/heads/" .. plugin.branch)) or "HEAD"
      if plugin.commit then
        return plugin.commit
      end
      local remote = lib.command({ "git", "ls-remote", plugin.url, ref })
      return assert(remote:match("^(%x+)"), "could not resolve missing plugin")
    end
  end)
  local status = not ok and "blocked" or (not current and "planned" or (current == candidate and "installed" or "update"))
  targets[name] = ok and candidate or nil
  emit(
    "neovim-plugin",
    name,
    status,
    plugin.url or plugin.dir,
    plugin.dir,
    current,
    ok and candidate or nil,
    ok and (status == "installed" and "current" or "approved plugin commit") or candidate
  )
end

local ts = config.plugins["nvim-treesitter"]
if not ts or not ts._.installed then
  emit(
    "treesitter-parsers",
    "configured parser set",
    "check",
    "nvim-treesitter parser manifest",
    lib.data .. "/site/parser",
    nil,
    nil,
    "deferred until Treesitter bootstrap; display and confirm parser plan afterwards"
  )
elseif not targets["nvim-treesitter"] then
  emit(
    "treesitter-parsers",
    "configured parser set",
    "blocked",
    "nvim-treesitter parser manifest",
    ts.dir,
    nil,
    nil,
    "candidate Treesitter manifest is unavailable"
  )
else
  local ok, manifest = pcall(lib.manifest, ts.dir, targets["nvim-treesitter"])
  if not ok then
    emit("treesitter-parsers", "configured parser set", "blocked", "nvim-treesitter parser manifest", ts.dir, nil, nil, manifest)
  else
    local installed = lib.installed_parsers()
    local names = vim.deepcopy(installed)
    for _, name in ipairs(spec.parsers) do
      names[name] = true
    end
    local function dependencies(name)
      for _, dependency in ipairs(manifest[name] and manifest[name].requires or {}) do
        if not names[dependency] then
          names[dependency] = true
          dependencies(dependency)
        end
      end
    end
    for name in pairs(names) do
      dependencies(name)
    end
    local parser_rows = {}
    local plugin_commit = assert(git.info(ts.dir)).commit
    for _, name in ipairs(lib.keys(names)) do
      local entry = manifest[name]
      local info = entry and entry.install_info
      local target = info and info.revision or (entry and ("queries:" .. targets["nvim-treesitter"]))
      local current = lib.language_version(name, target, ts.dir, plugin_commit)
      local status = not target and "blocked" or (not current and "planned" or (current == target and "installed" or "update"))
      local probe = info and (lib.data .. "/site/parser-info/" .. name .. ".revision") or (lib.data .. "/site/queries/" .. name)
      parser_rows[name] = {
        status = status,
        origin = info and info.url or ts.url,
        probe = probe,
        current = current,
        target = target,
        reason = target and (status == "installed" and "current" or "candidate parser manifest revision") or "parser revision is unavailable",
      }
    end
    local function rebuild_dependencies(name)
      for _, dependency in ipairs(manifest[name] and manifest[name].requires or {}) do
        local row = parser_rows[dependency]
        if row and row.status == "installed" then
          row.status = "update"
          row.reason = "rebuilt by " .. name .. " installation"
          rebuild_dependencies(dependency)
        end
      end
    end
    for name, row in pairs(parser_rows) do
      if row.status == "planned" or row.status == "update" then
        rebuild_dependencies(name)
      end
    end
    for _, name in ipairs(lib.keys(parser_rows)) do
      local row = parser_rows[name]
      emit("treesitter-parsers", name, row.status, row.origin, row.probe, row.current, row.target, row.reason)
    end
  end
end

if not vim.uv.fs_stat(lib.lazy_root .. "/mason.nvim/lua/mason/init.lua") then
  emit(
    "mason-packages",
    "configured Mason package set",
    "check",
    "mason-registry",
    lib.data .. "/mason/packages",
    nil,
    nil,
    "deferred until Mason bootstrap; display and confirm package plan afterwards"
  )
else
  local registry = lib.mason()
  local done, success = false, false
  registry.update(function(ok)
    success, done = ok, true
  end)
  if not vim.wait(120000, function()
    return done
  end, 100) or not success then
    emit(
      "mason-packages",
      "configured Mason package set",
      "blocked",
      "mason-registry",
      lib.data .. "/mason/packages",
      nil,
      nil,
      "Mason registry refresh failed"
    )
  else
    local names = { gitleaks = true }
    for _, name in ipairs(registry.get_installed_package_names()) do
      names[name] = true
    end
    local configured = {}
    for _, name in ipairs(spec.lsp_servers) do
      configured[name] = true
    end
    for _, package in ipairs(registry.get_all_package_specs()) do
      if package.neovim and configured[package.neovim.lspconfig] then
        names[package.name] = true
        configured[package.neovim.lspconfig] = nil
      end
    end
    for name in pairs(configured) do
      emit("mason-packages", name, "blocked", "mason-registry", lib.data .. "/mason/packages", nil, nil, "configured LSP has no registry package")
    end
    for _, name in ipairs(lib.keys(names)) do
      local ok, package = pcall(registry.get_package, name)
      local current, target
      if ok then
        ok, current, target = pcall(function()
          return package:get_installed_version(), package:get_latest_version()
        end)
      end
      ok = ok and type(target) == "string" and target ~= ""
      local status = not ok and "blocked" or (not current and "planned" or (current == target and "installed" or "update"))
      emit(
        "mason-packages",
        name,
        status,
        "mason-registry",
        lib.data .. "/mason/packages/" .. name,
        ok and current or nil,
        ok and target or nil,
        ok and (status == "installed" and "current" or "registry version") or "Mason package metadata failed"
      )
    end
  end
end
