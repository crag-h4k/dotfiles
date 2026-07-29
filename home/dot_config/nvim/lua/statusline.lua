-- home/dot_config/nvim/lua/statusline.lua
-- lualine statusline driven by the shared base16 palette (dotfiles_palette), so
-- a palette switch propagates here with no per-theme wiring. The occult
-- diagnostic icons (skull / pentagram / info / cross) and the current-line
-- diagnostic message are carried over from the previous lightline config; the
-- git branch and add/change/delete hunk counts (from gitsigns) are folded in.

local M = {}

local ERROR = vim.diagnostic.severity.ERROR
local WARN = vim.diagnostic.severity.WARN
local INFO = vim.diagnostic.severity.INFO
local HINT = vim.diagnostic.severity.HINT

local SEV_ICON = {
  [ERROR] = "☠",
  [WARN] = "⛧",
  [INFO] = "ℹ",
  [HINT] = "☦",
}

local function trunc(s, max)
  if not s or s == "" then
    return ""
  end
  if #s <= max then
    return s
  end
  return s:sub(1, max - 1) .. "…"
end

-- Top-severity diagnostic on the current line, or nil. Cheap enough to call per
-- redraw: it only scans the diagnostics attached to the cursor line.
local function top_line_diag()
  local lnum = (vim.api.nvim_win_get_cursor(0)[1] or 1) - 1
  local diags = vim.diagnostic.get(0, { lnum = lnum })
  if not diags or #diags == 0 then
    return nil
  end
  table.sort(diags, function(a, b)
    return (a.severity or 999) < (b.severity or 999)
  end)
  return diags[1]
end

-- Current-line diagnostic, icon + message, truncated. Empty when the cursor is
-- on a clean line so lualine hides the component (see the cond in setup).
function M.diag_message()
  local d = top_line_diag()
  if not d then
    return ""
  end
  local icon = SEV_ICON[d.severity] or "!"
  return trunc(("%s %s"):format(icon, (d.message or ""):gsub("%s+", " ")), 120)
end

-- gitsigns publishes per-buffer hunk counts; feed them to lualine's diff
-- component so the numbers track the buffer, not a git subprocess.
local function gitsigns_diff()
  local gsd = vim.b.gitsigns_status_dict
  if not gsd then
    return nil
  end
  return { added = gsd.added, modified = gsd.changed, removed = gsd.removed }
end

-- Build a lualine theme from the shared base16 table (the same module
-- base16-nvim consumes), so section colors match nvim syntax and follow a
-- palette switch. Explicit hex keeps the statusline independent of when
-- base16-nvim applies its highlight groups during startup.
local function build_theme(base)
  return {
    normal = {
      a = { fg = base.base00, bg = base.base0D, gui = "bold" },
      b = { fg = base.base05, bg = base.base02 },
      c = { fg = base.base04, bg = base.base01 },
    },
    insert = { a = { fg = base.base00, bg = base.base0B, gui = "bold" } },
    visual = { a = { fg = base.base00, bg = base.base0E, gui = "bold" } },
    replace = { a = { fg = base.base00, bg = base.base08, gui = "bold" } },
    command = { a = { fg = base.base00, bg = base.base0A, gui = "bold" } },
    inactive = {
      a = { fg = base.base04, bg = base.base01 },
      b = { fg = base.base04, bg = base.base01 },
      c = { fg = base.base03, bg = base.base00 },
    },
  }
end

function M.setup()
  local ok, lualine = pcall(require, "lualine")
  if not ok then
    return
  end

  local base = require("dotfiles_palette").base16

  -- Severity -> palette hex, shared by the count component and the message color.
  local sev_hl = {
    [ERROR] = base.base08,
    [WARN] = base.base0A,
    [INFO] = base.base0C,
    [HINT] = base.base0D,
  }

  local diag_message = {
    M.diag_message,
    cond = function()
      return top_line_diag() ~= nil
    end,
    color = function()
      local d = top_line_diag()
      return { fg = (d and sev_hl[d.severity]) or base.base05 }
    end,
  }

  lualine.setup({
    options = {
      theme = build_theme(base),
      icons_enabled = true,
      globalstatus = false,
      section_separators = { left = "", right = "" },
      component_separators = { left = "", right = "" },
      refresh = { statusline = 1000 },
    },
    sections = {
      lualine_a = {
        "mode",
        {
          function()
            return "PASTE"
          end,
          cond = function()
            return vim.o.paste
          end,
        },
      },
      lualine_b = {
        { "branch", icon = "" },
        {
          "diff",
          source = gitsigns_diff,
          diff_color = {
            added = { fg = base.base0B },
            modified = { fg = base.base09 },
            removed = { fg = base.base08 },
          },
        },
      },
      lualine_c = {
        {
          "filename",
          path = 1,
          symbols = { modified = " ●", readonly = " ", unnamed = "[No Name]" },
        },
        diag_message,
      },
      lualine_x = {
        {
          "diagnostics",
          sources = { "nvim_diagnostic" },
          symbols = { error = "☠ ", warn = "⛧ ", info = "ℹ ", hint = "☦ " },
          diagnostics_color = {
            error = { fg = sev_hl[ERROR] },
            warn = { fg = sev_hl[WARN] },
            info = { fg = sev_hl[INFO] },
            hint = { fg = sev_hl[HINT] },
          },
        },
        "encoding",
        "fileformat",
        "filetype",
      },
      lualine_y = { "progress" },
      lualine_z = { "location" },
    },
    inactive_sections = {
      lualine_c = { { "filename", path = 1 } },
      lualine_x = { "location" },
    },
  })

  -- lualine refreshes on a 1s timer plus window events, which lags the
  -- current-line diagnostic message and the diff counts. Nudge it on the same
  -- events the old lightline config watched so both stay responsive.
  local group = vim.api.nvim_create_augroup("UserStatuslineRefresh", { clear = true })
  vim.api.nvim_create_autocmd({ "DiagnosticChanged", "CursorMoved", "BufEnter" }, {
    group = group,
    callback = function()
      require("lualine").refresh({ place = { "statusline" } })
    end,
  })
end

return M
