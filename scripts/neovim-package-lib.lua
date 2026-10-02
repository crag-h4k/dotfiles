-- Shared metadata access for Neovim package planning and application.
local M = {}
M.data = vim.fn.stdpath("data")
M.config = vim.fn.stdpath("config")
M.lazy_root = M.data .. "/lazy"

function M.read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return vim.trim(content)
end

function M.command(args)
  local result = vim.system(args, { text = true }):wait(120000)
  assert(result.code == 0, vim.trim(result.stderr or "command failed"))
  return vim.trim(result.stdout or "")
end

function M.clean_plugin(directory, origin, treesitter)
  local status = M.command({ "git", "--no-optional-locks", "-C", directory, "status", "--porcelain", "--untracked-files=all" })
  if status ~= "" then
    for line in status:gmatch("[^\r\n]+") do
      local generated = treesitter and (line:match("^%?%? parser/[^/]+%.so$") or line:match("^%?%? parser%-info/[^/]+%.revision$"))
      assert(generated, "plugin has local changes")
    end
  end
  if origin then
    local actual = M.command({ "git", "-C", directory, "config", "--get", "remote.origin.url" })
    assert(actual == origin, "plugin origin changed")
  end
end

function M.keys(values)
  local names = vim.tbl_keys(values)
  table.sort(names)
  return names
end

function M.emit(source, name, status, origin, probe, current, target, reason)
  local values = { source, name, status, "floating", origin, probe, current or "-", target or "-", reason }
  for i, value in ipairs(values) do
    values[i] = tostring(value):gsub("[\t\r\n]", " ")
  end
  io.stdout:write(table.concat(values, "\t") .. "\n")
end

function M.spec()
  vim.env.DOTFILES_NVIM_PACKAGE_SPEC = "1"
  local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
  local root = vim.env.DOTFILES_SOURCE_ROOT or vim.fs.dirname(here)
  local init = root .. "/home/dot_config/nvim/init.lua"
  if not vim.uv.fs_stat(init) then
    init = M.config .. "/init.lua"
  end
  local ok, result = pcall(dofile, init)
  vim.env.DOTFILES_NVIM_PACKAGE_SPEC = nil
  assert(ok, result)
  assert(type(result) == "table" and result.plugins, "Neovim config does not export package specifications")
  return result
end

function M.lazy(spec)
  vim.opt.rtp:prepend(M.lazy_root .. "/lazy.nvim")
  local config = require("lazy.core.config")
  for _, plugin in ipairs(spec.plugins) do
    if type(plugin) == "table" and plugin[1] == "nvim-treesitter/nvim-treesitter" then
      plugin.build = false -- Parsers have their own approved revisions.
    end
  end
  config.setup({
    spec = spec.plugins,
    local_spec = false,
    install = { missing = false },
    checker = { enabled = false },
    change_detection = { enabled = false },
    pkg = { enabled = false },
    rocks = { enabled = false },
    headless = { process = false, log = false, task = false, colors = false },
  })
  require("lazy.core.plugin").load()
  return config
end

function M.plugin_error(plugin)
  for _, task in ipairs(plugin._.tasks or {}) do
    if task:has_errors() then
      return task:output(vim.log.levels.ERROR)
    end
  end
end

function M.manifest(plugin_dir, commit)
  local content = M.command({ "git", "-C", plugin_dir, "show", commit .. ":lua/nvim-treesitter/parsers.lua" })
  local chunk = assert(loadstring(content, "Treesitter parser manifest"))
  setfenv(chunk, {})
  return chunk()
end

function M.installed_parsers()
  local result = {}
  local directory = M.data .. "/site/parser"
  if vim.uv.fs_stat(directory) then
    for name in vim.fs.dir(directory) do
      result[name:gsub("%.[^.]+$", "")] = true
    end
  end
  return result
end

function M.parser_version(name)
  if not M.installed_parsers()[name] then
    return nil
  end
  return M.read(M.data .. "/site/parser-info/" .. name .. ".revision")
end

function M.language_version(name, target, plugin_dir, plugin_commit)
  if target and target:match("^queries:") then
    local queries = M.data .. "/site/queries/" .. name
    local expected = plugin_dir .. "/runtime/queries/" .. name
    if vim.uv.fs_realpath(queries) == expected then
      return "queries:" .. plugin_commit
    end
    return nil
  end
  return M.parser_version(name)
end

function M.mason()
  vim.opt.rtp:prepend(M.lazy_root .. "/mason.nvim")
  require("mason").setup()
  return require("mason-registry")
end

function M.rows(path)
  local result = {}
  for _, line in ipairs(vim.fn.readfile(path)) do
    local row = vim.split(line, "\t", { plain = true })
    if row[1] == "neovim-plugin" or row[1] == "treesitter-parsers" or row[1] == "mason-packages" then
      assert(#row == 9, "Invalid Neovim package plan row")
      result[#result + 1] = row
    end
  end
  return result
end

return M
