-- tests/test_neovim_update.lua
-- Exercise false and exceptional task completion without loading plugins.

local source = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fs.dirname(vim.fs.dirname(source))
local lib = dofile(repo .. "/scripts/neovim-update-lib.lua")

assert(lib.wait_task(function()
  return {
    wait = function()
      return true
    end,
  }
end, 1))
assert(lib.wait_task(function()
  return {
    wait = function()
      return nil
    end,
  }
end, 1))
assert(not lib.wait_task(function()
  return {
    wait = function()
      return false
    end,
  }
end, 1))
assert(not lib.wait_task(function()
  return {
    wait = function()
      error("wait failed")
    end,
  }
end, 1))
assert(not lib.wait_task(function()
  error("start failed")
end, 1))

vim.cmd("qa")
