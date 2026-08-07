-- Neovim config (lazy.nvim + mason.nvim)
-- Uses Lua modules from this repo's `lua/` directory.
do
  local src = debug.getinfo(1, "S").source
  local this_file = (type(src) == "string" and src:sub(1, 1) == "@") and src:sub(2) or nil
  if this_file then
    -- init.lua may be loaded directly or via a symlink. Resolve the real
    -- path so we can find the sibling lua/ directory in either case.
    local real = (vim.loop and vim.loop.fs_realpath) and vim.loop.fs_realpath(this_file) or nil
    local roots = {
      vim.fn.fnamemodify(this_file, ":p:h"),
      real and vim.fn.fnamemodify(real, ":p:h") or nil,
    }
    for _, root in ipairs(roots) do
      if root and root ~= "" then
        package.path = package.path .. ";" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua"
      end
    end
  end
end
--
--
-- Oil.nvim works best with netrw disabled.
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Completion menu behaves like supertab (menu, no preselection)
vim.opt.completeopt = { "menu", "menuone", "noselect" }
vim.opt.shortmess:append("c")
vim.opt.pumheight = 12

-- Basic editor/UI settings (ported from ~/.vim/vimrc:9-57)
vim.cmd("syntax on")
vim.cmd("filetype plugin indent on")

-- Neovim always uses UTF-8 internally; keep this for parity with vimrc.
vim.opt.encoding = "utf-8"

vim.opt.wrap = true
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.ruler = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamed"
vim.opt.updatetime = 500

vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.incsearch = true
vim.opt.autowrite = true
vim.opt.hidden = true

vim.keymap.set("i", "fj", "<Esc>", { noremap = true })
vim.keymap.set("c", "fj", "<Esc>", { noremap = true })

local restore_cursor_group = vim.api.nvim_create_augroup("UserRestoreCursor", { clear = true })
vim.api.nvim_create_autocmd("BufReadPost", {
  group = restore_cursor_group,
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    local lcount = vim.api.nvim_buf_line_count(ev.buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
  desc = "Restore cursor to last position when reopening a file",
})

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

vim.opt.backspace = { "indent", "eol", "start" }
vim.opt.wildmenu = true
vim.opt.wildmode = { "list:longest", "full" }

-- More settings ported from ~/.vim/vimrc
vim.g.python_highlight_all = 1
vim.g.pymode_indent = 0

-- Python providers (Neovim mainly uses python3, but keep both for parity).
-- Venv lives in ~/.local/share (created by scripts/install-neovim.sh), kept out
-- of the chezmoi-managed ~/.config/nvim tree.
vim.g.python_host_prog = vim.fn.expand("$HOME/.local/share/nvim-venv/bin/python")
vim.g.python3_host_prog = vim.fn.expand("$HOME/.local/share/nvim-venv/bin/python3")

-- Filetype overrides / additions (ported from vimrc autocmds)
local ft_group = vim.api.nvim_create_augroup("UserFiletypeOverrides", { clear = true })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  group = ft_group,
  pattern = { "BUCK", "BUCKi" },
  command = "setfiletype starlark",
})
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = "*.go*", command = "setfiletype go" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = "*Dockerfile*", command = "setfiletype dockerfile" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  group = ft_group,
  pattern = { "*jenkinsfile*", "*Jenkinsfile*" },
  command = "setfiletype groovy",
})
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = "*.json*", command = "setfiletype json" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  group = ft_group,
  pattern = { "*.md*", "*.mdi" },
  command = "setfiletype markdown",
})
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = { "*.py", "*.pyi" }, command = "setfiletype python" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = { "*.rs", "*.rsi" }, command = "setfiletype rust" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, { group = ft_group, pattern = { "*.tf", "*.tfi" }, command = "setfiletype terraform" })
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  group = ft_group,
  pattern = { "*.y*ml*", "*.yaml.ig" },
  command = "setfiletype yaml",
})
vim.api.nvim_create_autocmd({ "BufNewFile", "BufRead" }, {
  group = ft_group,
  pattern = { "*.cfn.y*ml*", "*.template.y*ml*" },
  command = "setfiletype yaml.cloudformation",
})

-- Tabbing and indents
vim.opt.smarttab = true
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.cindent = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4

-- Tab remaps
vim.keymap.set("n", "<C-S-Enter>", "<cmd>tabe<cr>", { noremap = true })
vim.keymap.set("n", "<C-S-Tab>", "<cmd>tabp<cr>", { noremap = true })
vim.keymap.set("n", "<C-Tab>", "<cmd>tabn<cr>", { noremap = true })

-- Whitespace/listchars
vim.opt.listchars = { tab = ">-", trail = "-", nbsp = "_" }
vim.opt.list = true

-- No noise
vim.opt.errorbells = false
vim.opt.visualbell = false
vim.opt.belloff = "all"
vim.opt.timeoutlen = 500

-- Typos / helpers
vim.api.nvim_create_user_command("Q", "q", { force = true })
vim.api.nvim_create_user_command("W", "w", { force = true })
vim.api.nvim_create_user_command("WQ", "wq", { force = true })
vim.api.nvim_create_user_command("Wq", "wq", { force = true })

vim.api.nvim_create_user_command("Blanks", function()
  vim.cmd([[g/^\s*$/d]])
end, {})

vim.api.nvim_create_user_command("WS", function()
  vim.cmd([[%s/\s\+$//e]])
end, {})

vim.g.rainbow_active = 1
vim.opt.splitright = true

vim.g.LanguageClient_useVirtualText = 0

-- YAML-specific indentation tweaks
local yaml_group = vim.api.nvim_create_augroup("UserYamlFix", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = yaml_group,
  pattern = "yaml",
  callback = function()
    vim.opt_local.tabstop = 2
    vim.opt_local.softtabstop = 2
    vim.opt_local.shiftwidth = 2
    vim.opt_local.expandtab = true
    vim.opt_local.indentkeys:remove("0#")
    vim.opt_local.indentkeys:remove("<:>")
  end,
  desc = "YAML indent fixes",
})

-- OPA Rego globals (for autoformat/formatter integrations)
vim.g.formatdef_rego = [["opa fmt"]]
vim.g.formatters_rego = { "rego" }
vim.g.autoformat_autoindent = 0
vim.g.autoformat_retab = 0

vim.cmd([[command! Rando g/^/exec "move " .. rand() % (line('.'))]])

-- Live diff updates
local diff_group = vim.api.nvim_create_augroup("UserDiffUpdate", { clear = true })
vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
  group = diff_group,
  callback = function()
    pcall(vim.cmd, "diffupdate")
  end,
})

-- Folding defaults
vim.opt.foldmethod = "manual"
vim.opt.foldlevelstart = 99

-- Silence LSP log - default level floods lsp.log with workspace-root errors.
-- vim.lsp.set_log_level was deprecated; use vim.lsp.log.set_level.
vim.lsp.log.set_level(vim.lsp.log.levels.OFF)

-- Diagnostics
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "☠",
      [vim.diagnostic.severity.WARN] = "⛧",
      [vim.diagnostic.severity.INFO] = "ℹ",
      [vim.diagnostic.severity.HINT] = "☦",
    },
    numhl = {
      [vim.diagnostic.severity.WARN] = "WarningMsg",
    },
  },
  status = true,
  underline = true,
  virtual_text = false,
  virtual_lines = false,
})

-- Statusline (lualine) is configured by the lualine plugin spec below, which
-- calls require("statusline").setup() once the plugin and palette are loaded.

-- Bootstrap lazy.nvim (plugin manager for Neovim-only plugins)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local dotfiles_palette = require("dotfiles_palette")
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Per-host opt-in for the AI assistant. CodeCompanion ships your buffer contents
-- to Claude, so it stays OFF by default and only loads on hosts that explicitly
-- opt in by creating the sentinel file:
--   touch ~/.config/nvim/.codecompanion-enabled
-- A fresh clone on an unknown/sensitive host never loads it until you opt in.
local codecompanion_enabled = (vim.uv or vim.loop).fs_stat(vim.fn.stdpath("config") .. "/.codecompanion-enabled") ~= nil

local lsp_servers = {
  -- Modern nvim-lspconfig IDs. mason-lspconfig translates these to Mason
  -- package names and installs only servers that are currently absent.
  "bashls",
  "docker_language_server",
  "jinja_lsp",
  "jsonls",
  "lua_ls",
  "marksman",
  "pyright",
  "terraformls",
  "tflint",
  "yamlls",
  "gh_actions_ls",
}

require("lazy").setup({
  -- Shared palette selected by chezmoi and rendered into dotfiles_palette.lua.
  { dotfiles_palette.plugin, name = dotfiles_palette.lazy_name, lazy = false, priority = 1000 },

  -- Statusline: lualine themed from the shared base16 palette (dotfiles_palette).
  -- Pure Lua, no compiled deps; devicons is already pulled in by oil/fzf-lua.
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    lazy = false,
    config = function()
      require("statusline").setup()
    end,
  },

  -- File explorer / mass rename by editing a directory buffer
  {
    "stevearc/oil.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" }, -- optional, for icons
    opts = {
      default_file_explorer = true,
      view_options = { show_hidden = true },
    },
  },

  -- LSP server installer/manager
  {
    "mason-org/mason.nvim",
    lazy = false,
    config = function()
      require("mason").setup()

      -- Gitleaks is editor-specific here, so Mason owns this one executable.
      -- Deliberately install only when absent: startup never updates an
      -- installed package or reconciles its version.
      local registry = require("mason-registry")
      if not registry.is_installed("gitleaks") then
        -- A fresh host may not have a registry yet. Refresh metadata only while
        -- the executable is missing, then install it; never update an existing
        -- Gitleaks package during startup.
        registry.refresh(function(registry_ok)
          if not registry_ok then
            vim.notify("Mason registry refresh failed; skipped Gitleaks install", vim.log.levels.WARN)
            return
          end

          local package_ok, package = pcall(registry.get_package, "gitleaks")
          if not package_ok then
            vim.notify("Mason registry does not contain gitleaks", vim.log.levels.WARN)
            return
          end
          if not package:is_installed() and not package:is_installing() then
            package:install()
          end
        end)
      end

      require("gitleaks").setup()
    end,
  },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "neovim/nvim-lspconfig",
    },
    config = function()
      local capabilities = require("cmp_nvim_lsp").default_capabilities()

      -- Extend every nvim-lspconfig definition with completion capabilities,
      -- then apply the one server-specific override this config needs.
      vim.lsp.config("*", { capabilities = capabilities })
      vim.lsp.config("lua_ls", {
        settings = { Lua = { diagnostics = { globals = { "vim" } } } },
      })

      -- mason-lspconfig owns the desired LSP install set. Disable its default
      -- auto-enable so activation has one explicit modern path below.
      require("mason-lspconfig").setup({
        ensure_installed = lsp_servers,
        automatic_enable = false,
      })
      vim.lsp.enable(lsp_servers)
    end,
  },

  -- Completion stack with supertab-style mappings
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      luasnip.config.setup({})
      require("luasnip.loaders.from_vscode").lazy_load()

      local has_words_before = function()
        local _, col = unpack(vim.api.nvim_win_get_cursor(0))
        if col == 0 then
          return false
        end
        local current = vim.api.nvim_get_current_line()
        return current:sub(col, col):match("%s") == nil
      end

      cmp.setup({
        preselect = cmp.PreselectMode.None,
        completion = { completeopt = "menu,menuone,noselect" },
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"] = cmp.mapping.abort(),
        }),
        sources = {
          { name = "nvim_lsp" },
          { name = "path" },
          { name = "buffer" },
          { name = "luasnip" },
        },
      })
    end,
  },

  -- Treesitter: syntax-aware highlighting for the languages this config edits.
  -- Promoted to a top-level spec (it used to be only a CodeCompanion dependency,
  -- so a host without the AI opt-in fell back to `syntax on` and nothing else).
  -- base16-nvim already ships treesitter highlight groups, so this lights up
  -- under the house palette with no extra theme. Highlight only: the existing
  -- cindent / per-filetype indent rules above stay authoritative.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "bash",
        "dockerfile",
        "go",
        "hcl",
        "json",
        "lua",
        "markdown",
        "markdown_inline",
        "python",
        "rust",
        "terraform",
        "yaml",
      }
      local treesitter = require("nvim-treesitter")
      treesitter.setup()

      -- Install only the parsers this host is missing. The main branch's
      -- install() re-stages into a shared working dir under ~/.local/share/nvim,
      -- so calling it unconditionally on every startup re-downloads parsers that
      -- are already compiled and races when two nvim instances launch at once -
      -- that race, plus stale *-tmp extraction dirs, is what produces the
      -- "mv ... No such file or directory" errors. Diff against what is already
      -- installed and install the remainder once; use :TSUpdate to refresh.
      local installed = {}
      for _, name in ipairs(treesitter.get_installed("parsers")) do
        installed[name] = true
      end
      local missing = {}
      for _, name in ipairs(parsers) do
        if not installed[name] then
          missing[#missing + 1] = name
        end
      end
      if #missing > 0 then
        treesitter.install(missing)
      end

      -- The main-branch rewrite delegates highlighting to Neovim. Parser names
      -- and filetypes are not always identical (bash -> sh; markdown_inline is
      -- an injection), so attach only to the filetypes backed by the list above.
      -- A missing/in-flight parser falls back to `syntax on` without breaking
      -- the buffer; reopening it after installation attaches Treesitter.
      vim.api.nvim_create_autocmd("FileType", {
        pattern = {
          "bash",
          "dockerfile",
          "go",
          "hcl",
          "json",
          "jsonc",
          "lua",
          "markdown",
          "python",
          "rust",
          "sh",
          "terraform",
          "terraform-vars",
          "yaml",
        },
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },

  -- Git gutter signs + hunk stage/reset/preview for a git-heavy day.
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local function map(mode, lhs, rhs, opts)
          opts = opts or {}
          opts.buffer = bufnr
          vim.keymap.set(mode, lhs, rhs, opts)
        end
        -- Hunk navigation, falling through to vim's default ]c/[c in diff mode.
        map("n", "]c", function()
          if vim.wo.diff then
            return "]c"
          end
          vim.schedule(function()
            gs.nav_hunk("next")
          end)
          return "<Ignore>"
        end, { expr = true, desc = "Gitsigns: next hunk" })
        map("n", "[c", function()
          if vim.wo.diff then
            return "[c"
          end
          vim.schedule(function()
            gs.nav_hunk("prev")
          end)
          return "<Ignore>"
        end, { expr = true, desc = "Gitsigns: prev hunk" })
        map("n", "<leader>hs", gs.stage_hunk, { desc = "Gitsigns: stage hunk" })
        map("n", "<leader>hr", gs.reset_hunk, { desc = "Gitsigns: reset hunk" })
        map("n", "<leader>hp", gs.preview_hunk, { desc = "Gitsigns: preview hunk" })
        map("n", "<leader>hb", function()
          gs.blame_line({ full = true })
        end, { desc = "Gitsigns: blame line" })
      end,
    },
  },

  -- Popup that surfaces the <leader> keymaps (CodeCompanion, gitsigns, fzf-lua).
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },

  -- Fuzzy finder reusing the fzf binary already on PATH (lighter than telescope:
  -- no compiled fzf-native, no plenary). Grep uses ripgrep, also installed.
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "FzfLua",
    keys = {
      { "<leader>ff", "<cmd>FzfLua files<cr>", desc = "FzfLua: files" },
      { "<leader>fg", "<cmd>FzfLua live_grep<cr>", desc = "FzfLua: live grep" },
      { "<leader>fb", "<cmd>FzfLua buffers<cr>", desc = "FzfLua: buffers" },
      { "<leader>fh", "<cmd>FzfLua help_tags<cr>", desc = "FzfLua: help tags" },
    },
    opts = {},
  },

  -- AI chat / coding assistant (CodeCompanion). Gated by the sentinel file above,
  -- so this whole spec is invisible to lazy.nvim on hosts that did not opt in.
  --
  -- Backed by the Claude Code ACP adapter: it reuses your existing Claude Code
  -- login instead of a separate API key. Requirements on an enabled host:
  --   1. claude-agent-acp on PATH:  npm i -g @agentclientprotocol/claude-agent-acp
  --   2. auth: an existing `claude` login works, or run `claude setup-token` and
  --      export CLAUDE_CODE_OAUTH_TOKEN.
  -- Override the model per-host via env or by extending the acp adapter in opts.
  {
    "olimorris/codecompanion.nvim",
    enabled = codecompanion_enabled,
    cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
    keys = {
      -- Normal + visual: <space>cc opens/closes the chat (a "claude session").
      { "<leader>cc", "<cmd>CodeCompanionChat Toggle<cr>", mode = { "n", "v" }, desc = "CodeCompanion: toggle chat" },
      { "<leader>ca", "<cmd>CodeCompanionActions<cr>", mode = { "n", "v" }, desc = "CodeCompanion: actions palette" },
      -- Visual: send the current selection into the chat buffer.
      { "ga", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "CodeCompanion: add selection to chat" },
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- render-markdown needs the markdown treesitter parsers to render the chat.
      -- Treesitter (markdown + markdown_inline included) is configured by the
      -- top-level spec above; depend on it by name so it loads first.
      "nvim-treesitter/nvim-treesitter",
      -- Pretty chat buffer: render markdown in the `codecompanion` filetype, not
      -- just plain `markdown` files. This is what makes the chat look like the
      -- CodeCompanion screenshots (needs a Nerd Font in the terminal for icons).
      {
        "MeanderingProgrammer/render-markdown.nvim",
        ft = { "markdown", "codecompanion" },
        opts = { file_types = { "markdown", "codecompanion" } },
      },
    },
    opts = {
      -- The Claude Code ACP adapter only supports the chat strategy. Inline and
      -- cmd interactions require an HTTP adapter (API key), so leave them at their
      -- defaults and drive everything through the chat buffer.
      interactions = {
        chat = { adapter = "claude_code" },
      },
    },
    config = function(_, opts)
      require("codecompanion").setup(opts)
    end,
  },

  -- Markdown linting via markdownlint-cli2
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = { markdown = { "markdownlint-cli2" } }
      lint.linters["markdownlint-cli2"].args = {
        "--config",
        vim.fn.expand("~/.markdownlint.yaml"),
      }
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },

  -- Formatting via conform.nvim, backed by prettierd (a persistent Prettier
  -- daemon on PATH). Scoped to the structured-config filetypes prettier handles
  -- well; terraform/python/go/rust/lua/bash keep their own tools, and markdown
  -- is left to markdownlint above. Manual only: <leader>f formats the buffer,
  -- nothing reformats on save.
  {
    "stevearc/conform.nvim",
    keys = {
      {
        "<leader>f",
        function()
          require("conform").format({ async = true, lsp_format = "never" })
        end,
        mode = { "n", "v" },
        desc = "Conform: format buffer (prettierd)",
      },
    },
    opts = {
      formatters_by_ft = {
        json = { "prettierd" },
        jsonc = { "prettierd" },
        yaml = { "prettierd" },
      },
    },
  },
})

-- base16-nvim's setup() applies the scheme directly from the 16 colors, so
-- there is no separate :colorscheme to run.
dotfiles_palette.setup()

-- Replace NERDTree's old <C-n> toggle with Oil
vim.keymap.set("n", "<C-n>", "<CMD>Oil<CR>", { desc = "Oil: file explorer" })

-- CodeCompanion command alias: ":cc" expands to ":CodeCompanionChat" (opens the
-- chat), without shadowing anything else (only fires when the whole command line
-- is exactly "cc"). The Claude Code ACP adapter is chat-only, so the alias points
-- at the chat rather than the inline ":CodeCompanion" command. <space>cc toggles.
if codecompanion_enabled then
  vim.cmd([[cnoreabbrev <expr> cc (getcmdtype() ==# ':' && getcmdline() ==# 'cc') ? 'CodeCompanionChat' : 'cc']])
end
