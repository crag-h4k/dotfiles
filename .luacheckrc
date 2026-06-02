-- Luacheck config for the Neovim Lua in this repo (dot_config/nvim).
-- Neovim runs LuaJIT and injects the global `vim` table. `vim` is in `globals`
-- (not `read_globals`) because the config sets vim.g.* / vim.opt.* fields.
std = "luajit"
globals = { "vim" }

-- init.lua carries long descriptive comments and plugin-spec strings; line
-- length is not a useful signal for editor config.
max_line_length = false
