-- scripts/neovim-update-lib.lua
-- Small testable helpers for the headless Neovim package updater.

local M = {}

function M.wait_task(start, timeout)
  local start_ok, task = pcall(start)
  if not start_ok or not task then
    return false
  end
  local wait_ok, wait_result = pcall(function()
    return task:wait(timeout)
  end)
  return wait_ok and wait_result ~= false
end

return M
