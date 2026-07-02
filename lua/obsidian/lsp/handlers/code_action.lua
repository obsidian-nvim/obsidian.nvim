local actions = require("obsidian.lsp.handlers._code_action").actions

---@param code_actions table<string, lsp.CodeAction>
---@param note obsidian.Note
---@return lsp.CodeAction[]
local function get_commands_by_context(code_actions, note)
  local out = {}
  for _, code_action in ipairs(vim.tbl_values(code_actions)) do
    local data = code_action.data
    ---@cast data { cond: fun(note: obsidian.Note): boolean }
    if data.cond(note) then
      out[#out + 1] = code_action
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
