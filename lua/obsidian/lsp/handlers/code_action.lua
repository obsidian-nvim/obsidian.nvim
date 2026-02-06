local actions = require("obsidian.lsp.handlers._code_action").actions

---@param code_actions lsp.CodeAction[]
---@param in_selection boolean
---@return string[]
local function get_commands_by_context(code_actions, in_selection)
  return vim
    .iter(vim.tbl_values(code_actions))
    :filter(function(code_action)
      if in_selection then
        return code_action.data.range ~= nil
      else
        return code_action.data.range == nil
      end
    end)
    :totable()
end

---@param params lsp.CodeActionParams
return function(params, handler)
  local range = params.range
  local in_selection = range.start ~= range["end"]
  local res = get_commands_by_context(actions, in_selection)

  handler(nil, res)
end
