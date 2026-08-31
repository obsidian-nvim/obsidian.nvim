local actions = require("obsidian.lsp.handlers._code_action").actions

---@param title string|fun(note: obsidian.Note): string
---@param note obsidian.Note
---@return string
local function eval_title(title, note)
  if type(title) == "function" then
    return title(note)
  end
  return title
end

---@param code_actions table<string, obsidian.lsp.CodeAction>
---@param note obsidian.Note
---@return lsp.CodeAction[]
local function get_commands_by_context(code_actions, note)
  local out = {}
  for _, code_action in ipairs(vim.tbl_values(code_actions)) do
    local data = code_action.data
    if data.cond(note) then
      local title = eval_title(data.title, note)
      local command = vim.tbl_extend("force", code_action.command or {}, { title = title })
      out[#out + 1] = vim.tbl_extend("force", code_action, { title = title, command = command })
    end
  end
  return out
end

---@param params lsp.CodeActionParams
return function(params, handler)
  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  local note = require("obsidian.note").from_buffer(buf)
  local res = get_commands_by_context(actions, note)
  handler(nil, res)
end
