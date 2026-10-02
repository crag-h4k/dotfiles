-- Apply only the Neovim versions recorded in the approved package plan.
local source = debug.getinfo(1, "S").source:sub(2)
local directory = vim.fs.dirname(source)
local lib = dofile(directory .. "/neovim-package-lib.lua")
local tasks = dofile(directory .. "/neovim-update-lib.lua")
local failures = {}

local function failed(label, detail)
  failures[#failures + 1] = label
  io.stderr:write("dotfiles: " .. label .. ": " .. tostring(detail) .. "\n")
end

local function apply()
  local rows = lib.rows(assert(arg[1], "approved Neovim package plan is required"))
  local actions = {}
  for _, row in ipairs(rows) do
    if row[3] == "planned" or row[3] == "update" then
      actions[#actions + 1] = row
    elseif row[3] == "blocked" then
      failed(row[2], row[9])
    end
  end
  if #actions == 0 then
    print("dotfiles: Neovim packages are current; no installations")
    return
  end

  local config = lib.lazy(lib.spec())
  local git = require("lazy.manage.git")
  local ts_before = config.plugins["nvim-treesitter"]
  for _, row in ipairs(actions) do
    if row[1] == "treesitter-parsers" then
      local commit = assert(git.info(ts_before.dir)).commit
      assert((lib.language_version(row[2], row[8], ts_before.dir, commit) or "-") == row[7], "parser changed since approval: " .. row[2])
    end
  end
  local lock, install, update = {}, {}, {}
  for _, row in ipairs(rows) do
    if row[1] == "neovim-plugin" and row[8] ~= "-" then
      local plugin = assert(config.plugins[row[2]], "plugin is no longer configured: " .. row[2])
      lock[row[2]] = { branch = plugin.branch or "main", commit = row[8] }
      if row[3] == "planned" or row[3] == "update" then
        assert(plugin.dir == row[6] and plugin.url == row[5], "plugin configuration changed since approval: " .. row[2])
        if plugin._.installed then
          lib.clean_plugin(plugin.dir, row[5])
        end
        local current = git.info(plugin.dir)
        assert((current and current.commit or "-") == row[7], "plugin changed since approval: " .. row[2])
        table.insert(row[3] == "planned" and install or update, row[2])
      end
    end
  end
  if #install + #update > 0 then
    local original_lock = config.options.lockfile
    local approved_lock = vim.fn.tempname()
    config.options.lockfile = approved_lock
    local lock_state = require("lazy.manage.lock")
    local function freeze_lock()
      vim.fn.writefile({ vim.json.encode(lock) }, approved_lock)
      lock_state.lock = vim.deepcopy(lock)
      lock_state._loaded = true
    end
    local manager = require("lazy.manage")
    if #install > 0 then
      freeze_lock()
      manager.install({ plugins = install, lockfile = true, show = false, wait = true })
    end
    if #update > 0 then
      freeze_lock()
      manager.update({ plugins = update, lockfile = true, show = false, wait = true })
    end
    local saved = lib.read(original_lock)
    saved = saved and vim.json.decode(saved) or {}
    for _, name in ipairs(vim.list_extend(install, update)) do
      local plugin = config.plugins[name]
      local current = git.info(plugin.dir)
      local err = lib.plugin_error(plugin)
      if err or not current or current.commit ~= lock[name].commit then
        failed(name, err or "installed plugin does not match approved commit")
      else
        saved[name] = lock[name]
      end
    end
    vim.fn.writefile({ vim.json.encode(saved) }, original_lock)
    config.options.lockfile = original_lock
    lock_state._loaded = false
    vim.fn.delete(approved_lock)
  end

  local parser_rows = {}
  for _, row in ipairs(actions) do
    if row[1] == "treesitter-parsers" then
      parser_rows[#parser_rows + 1] = row
    end
  end
  if #parser_rows > 0 then
    local ts = config.plugins["nvim-treesitter"]
    local approved = assert(lock["nvim-treesitter"], "Treesitter plugin commit is absent from plan").commit
    local current = git.info(ts.dir)
    assert(current and current.commit == approved, "Treesitter plugin does not match the approved parser manifest")
    vim.opt.rtp:prepend(ts.dir)
    local manifest = require("nvim-treesitter.parsers")
    local names = {}
    for _, row in ipairs(parser_rows) do
      local info = manifest[row[2]] and manifest[row[2]].install_info
      local target = info and info.revision or (manifest[row[2]] and ("queries:" .. approved))
      assert(target == row[8], "parser revision changed since approval: " .. row[2])
      names[#names + 1] = row[2]
    end
    local approved_names = {}
    for _, name in ipairs(names) do
      approved_names[name] = true
    end
    for _, name in ipairs(require("nvim-treesitter.config").norm_languages(names, { unsupported = true })) do
      assert(approved_names[name], "unapproved implicit parser dependency: " .. name)
    end
    local treesitter = require("nvim-treesitter")
    treesitter.setup()
    if not tasks.wait_task(function()
      return treesitter.install(names, { force = true })
    end, 300000) then
      failed("Treesitter", "parser installation failed")
    end
    for _, row in ipairs(parser_rows) do
      if lib.language_version(row[2], row[8], ts.dir, approved) ~= row[8] then
        failed(row[2], "installed parser does not match approved revision")
      end
    end
  end

  local registry
  for _, row in ipairs(actions) do
    if row[1] == "mason-packages" then
      registry = registry or lib.mason()
      local package = registry.get_package(row[2])
      assert((package:get_installed_version() or "-") == row[7], "Mason package changed since approval: " .. row[2])
      local done, success = false, false
      package:install({ version = row[8] }, function(ok)
        success, done = ok, true
      end)
      if not vim.wait(300000, function()
        return done
      end, 100) or not success then
        failed(row[2], "Mason package installation failed")
      elseif package:get_installed_version() ~= row[8] then
        failed(row[2], "installed Mason package does not match approved version")
      end
    end
  end
end

local ok, err = pcall(apply)
if not ok then
  failed("Neovim package application", err)
end
if #failures > 0 then
  vim.cmd("cquit 1")
else
  vim.cmd("qa")
end
