local M = {}

local namespace = vim.api.nvim_create_namespace("gitleaks")
local jobs = {}
local generations = {}
local last_error = nil

-- These are dependency, generated-state, or plugin-internal paths rather than
-- authored project buffers. Projects can add content-specific exceptions in a
-- root .gitleaks.toml; this list is intentionally path-only and conservative.
local excluded_path_segments = {
  "/.git/",
  "/.terraform/",
  "/.cache/",
  "/node_modules/",
  "/vendor/",
}

local excluded_filetypes = {
  gitcommit = true,
  gitrebase = true,
  help = true,
  lazy = true,
  mason = true,
  oil = true,
  qf = true,
  terminal = true,
}

local function normalized_path(path)
  return vim.fs.normalize(path):gsub("\\", "/")
end

local function path_is_excluded(path)
  local normalized = "/" .. normalized_path(path):gsub("^/+", "") .. "/"
  for _, segment in ipairs(excluded_path_segments) do
    if normalized:find(segment, 1, true) then
      return true
    end
  end
  return false
end

local function scan_context(filename)
  local directory = vim.fs.dirname(filename)
  local config = vim.fs.find(".gitleaks.toml", {
    path = directory,
    type = "file",
    upward = true,
  })[1]
  local root = config and vim.fs.dirname(config) or vim.fs.root(filename, { ".git" }) or directory
  local source = filename

  if vim.fs.relpath then
    source = vim.fs.relpath(root, filename) or filename
  elseif vim.startswith(filename, root .. "/") then
    source = filename:sub(#root + 2)
  end

  return {
    config = config,
    root = root,
    source = source,
  }
end

local function parse_report(contents)
  if not contents or contents == "" then
    return {}
  end

  local ok, findings = pcall(vim.json.decode, contents)
  if not ok or type(findings) ~= "table" then
    return nil, "Gitleaks returned an invalid JSON report"
  end

  local diagnostics = {}
  for _, finding in ipairs(findings) do
    if type(finding) == "table" then
      local start_line = math.max(tonumber(finding.StartLine) or 1, 1)
      local end_line = math.max(tonumber(finding.EndLine) or start_line, start_line)
      local start_column = math.max(tonumber(finding.StartColumn) or 1, 1)
      local end_column = math.max(tonumber(finding.EndColumn) or start_column, start_column)
      local rule = finding.RuleID or "unknown-rule"
      local description = finding.Description or "Possible secret"

      diagnostics[#diagnostics + 1] = {
        lnum = start_line - 1,
        end_lnum = end_line - 1,
        col = start_column - 1,
        end_col = end_column,
        severity = vim.diagnostic.severity.WARN,
        source = "gitleaks",
        code = rule,
        -- Never include Match, Line, or Secret: diagnostics can be copied into
        -- logs and issue trackers even though the CLI report itself is redacted.
        message = string.format("%s [%s]", description, rule),
      }
    end
  end
  return diagnostics
end

local function report_error(message)
  if message ~= last_error then
    last_error = message
    vim.notify(message, vim.log.levels.WARN)
  end
end

function M.should_scan(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  if vim.bo[bufnr].buftype ~= "" or excluded_filetypes[vim.bo[bufnr].filetype] then
    return false
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  return filename ~= "" and vim.fn.filereadable(filename) == 1 and not path_is_excluded(filename)
end

function M.scan(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.should_scan(bufnr) then
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.diagnostic.reset(namespace, bufnr)
    end
    return
  end
  if vim.fn.executable("gitleaks") ~= 1 then
    -- Mason may still be installing it. A later read/write retries naturally.
    vim.diagnostic.reset(namespace, bufnr)
    return
  end

  generations[bufnr] = (generations[bufnr] or 0) + 1
  local generation = generations[bufnr]
  if jobs[bufnr] then
    pcall(jobs[bufnr].kill, jobs[bufnr], 15)
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  local context = scan_context(filename)
  local report_path = vim.fn.tempname() .. "-gitleaks.json"
  local command = {
    "gitleaks",
    "dir",
    "--no-banner",
    "--no-color",
    "--redact",
    "--report-format=json",
    "--report-path=" .. report_path,
    "--exit-code=1",
  }
  if context.config then
    vim.list_extend(command, { "--config", context.config })
  end
  command[#command + 1] = context.source

  local started, job = pcall(vim.system, command, {
    cwd = context.root,
    text = true,
  }, vim.schedule_wrap(function(result)
    if generations[bufnr] == generation then
      jobs[bufnr] = nil
    end
    local report = ""
    if vim.fn.filereadable(report_path) == 1 then
      report = table.concat(vim.fn.readfile(report_path, "b"), "\n")
    end
    vim.fn.delete(report_path)

    if generations[bufnr] ~= generation or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    -- Gitleaks uses 1 for findings and 0 for a clean scan. Anything else is an
    -- execution/configuration failure and must not replace the last good result.
    if result.code ~= 0 and result.code ~= 1 then
      local detail = (result.stderr or ""):gsub("%s+$", "")
      report_error("Gitleaks scan failed" .. (detail ~= "" and ": " .. detail or ""))
      return
    end

    local diagnostics, parse_error = parse_report(report)
    if not diagnostics then
      report_error(parse_error)
      return
    end
    last_error = nil
    vim.diagnostic.set(namespace, bufnr, diagnostics, {
      severity_sort = true,
      underline = true,
      virtual_text = false,
    })
  end))

  if started then
    jobs[bufnr] = job
  else
    vim.fn.delete(report_path)
    report_error("Unable to start Gitleaks: " .. tostring(job))
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("UserGitleaks", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = group,
    callback = function(event)
      M.scan(event.buf)
    end,
    desc = "Scan normal file buffers for secrets without blocking",
  })
end

-- Kept small and side-effect free so the report-to-diagnostic boundary can be
-- checked headlessly without invoking the external scanner.
M._parse_report = parse_report

return M
