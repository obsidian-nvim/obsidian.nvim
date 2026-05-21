local _ca = require "obsidian.lsp.handlers._code_action"
local actions = _ca.actions
local resolve = _ca.resolve

---@param code_actions table<string, obsidian.lsp.CodeActionOpts>
---@param note obsidian.Note
---@return lsp.CodeAction[]
local function get_commands_by_context(code_actions, note)
  local out = {}
  for _, opts in ipairs(vim.tbl_values(code_actions)) do
    local cond = opts.cond
    if not cond or cond(note) then
      out[#out + 1] = resolve(opts, note)
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
