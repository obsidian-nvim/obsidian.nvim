local code_action = require "obsidian.lsp.handlers._code_action"
local Note = require "obsidian.note"

local M = {}

---@type obsidian.lsp.ResolvedCodeAction[]
local menu_actions = {}

---@type string[]
local menu_paths = {}

local function clear()
  for _, path in ipairs(menu_paths) do
    pcall(vim.api.nvim_cmd, { cmd = "aunmenu", args = { path } }, {})
  end
  menu_actions = {}
  menu_paths = {}
end

---@param name string
---@return string
local function escape_menu_name(name)
  name = name:gsub("[\r\n\t]", " "):gsub("&", "&&")
  return vim.fn.escape(name, [[ \.|]])
end

---Rebuild the Obsidian actions in the popup menu for the current context.
---@param bufnr integer?
M.refresh = function(bufnr)
  clear()

  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.b[bufnr].obsidian_buffer then
    return
  end

  local note = Note.from_buffer(bufnr)
  for _, item in ipairs(code_action.resolve(note)) do
    menu_actions[#menu_actions + 1] = item
    local path = "PopUp." .. escape_menu_name(item.name)
    menu_paths[#menu_paths + 1] = path
    vim.api.nvim_cmd({
      cmd = "anoremenu",
      args = {
        path,
        ("<Cmd>lua require('obsidian.popup').execute(%d)<CR>"):format(#menu_actions),
      },
      mods = { silent = true },
      magic = { bar = false, file = false },
    }, {})
  end
end

---@param item obsidian.lsp.ResolvedCodeAction
local function execute(item)
  local command = item.action.command
  if not command then
    require("obsidian.log").err("No command registered for code action '" .. item.name .. "'")
    return
  end

  local handler = vim.lsp.commands[command.command]
  if handler then
    handler(command, { bufnr = vim.api.nvim_get_current_buf() })
    return
  end

  local fallback = require("obsidian.actions")[item.name]
  if type(fallback) == "function" then
    vim.schedule(function()
      fallback(unpack(command.arguments or {}))
    end)
    return
  end

  require("obsidian.log").err("No handler registered for code action '" .. item.name .. "'")
end

---Execute an action from the current popup context.
---@param idx integer
M.execute = function(idx)
  local item = menu_actions[idx]
  if item then
    execute(item)
  end
end

return M
