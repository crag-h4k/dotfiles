-- scripts/update-neovim-packages.lua
-- Update installed Treesitter parsers and Mason packages during package mode.

local failures = {}
local source = debug.getinfo(1, "S").source:sub(2)
local update_lib = dofile(vim.fs.dirname(source) .. "/neovim-update-lib.lua")

local function failed(label)
  failures[#failures + 1] = label
  vim.api.nvim_err_writeln("dotfiles: " .. label .. " failed")
end

local treesitter_ok, treesitter = pcall(require, "nvim-treesitter")
if treesitter_ok then
  if not update_lib.wait_task(treesitter.update, 300000) then
    failed("Treesitter parser update")
  end
else
  failed("Treesitter plugin load")
end

local mason_ok, mason = pcall(require, "mason")
local registry_ok, registry = pcall(require, "mason-registry")
if mason_ok and registry_ok then
  mason.setup()
  local registry_done = false
  local registry_success = false
  registry.update(function(success)
    registry_success = success
    registry_done = true
  end)
  if not vim.wait(300000, function()
    return registry_done
  end, 100) or not registry_success then
    failed("Mason registry update")
  else
    local installed_ok, installed = pcall(registry.get_installed_packages)
    if not installed_ok then
      failed("Mason installed package lookup")
    else
      local pending = 0
      local mason_failures = 0
      for _, package in ipairs(installed) do
        local versions_ok, current, latest = pcall(function()
          return package:get_installed_version(), package:get_latest_version()
        end)
        if not versions_ok then
          mason_failures = mason_failures + 1
        elseif current ~= latest then
          pending = pending + 1
          local install_ok = pcall(function()
            package:install({}, function(success)
              if not success then
                mason_failures = mason_failures + 1
              end
              pending = pending - 1
            end)
          end)
          if not install_ok then
            mason_failures = mason_failures + 1
            pending = pending - 1
          end
        end
      end
      if pending > 0 and not vim.wait(300000, function()
        return pending == 0
      end, 100) then
        mason_failures = mason_failures + pending
      end
      if mason_failures > 0 then
        failed(("Mason package update (%d package errors)"):format(mason_failures))
      end
    end
  end
else
  failed("Mason plugin load")
end

if #failures > 0 then
  vim.cmd("cquit 1")
else
  print("dotfiles: Treesitter and Mason packages are current")
  vim.cmd("qa")
end
