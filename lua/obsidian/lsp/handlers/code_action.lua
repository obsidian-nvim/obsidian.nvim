local code_action = require "obsidian.lsp.handlers._code_action"

---@param params lsp.CodeActionParams
return function(params, handler)
  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  local note = require("obsidian.note").from_buffer(buf)
  local res = vim.tbl_map(function(item)
    return item.action
  end, code_action.resolve(note))
  handler(nil, res)
end
