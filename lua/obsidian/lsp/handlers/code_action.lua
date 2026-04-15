local actions = require("obsidian.lsp.handlers._code_action").actions

---@param code_actions lsp.CodeAction[]
---@param note obsidian.Note
---@return string[]
local function get_commands_by_context(code_actions, note)
  return vim
    .iter(vim.tbl_values(code_actions))
    :filter(function(code_action)
      return code_action.data.cond(note)
    end)
    :totable()
end

---@param params lsp.CodeActionParams
return function(params, handler)
  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  local note = require("obsidian.note").from_buffer(buf)
  local res = get_commands_by_context(actions, note)
  handler(nil, res)
end
