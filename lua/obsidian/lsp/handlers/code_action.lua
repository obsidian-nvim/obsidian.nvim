local actions = require("obsidian.lsp.handlers._code_action").actions

---@param acts lsp.CodeAction[]
---@param in_selection boolean
---@return string[]
local function get_commands_by_context(acts, in_selection)
  return vim
    .iter(acts)
    :filter(function(act)
      if in_selection then
        return act.data.range ~= nil
      else
        return act.data.range == nil
      end
    end)
    :totable()
end

---@param params lsp.CodeActionParams
return function(params, handler)
  local range = params.range

  local in_selection = range.start ~= range["end"]

  local res = get_commands_by_context(actions, in_selection)

  vim.tbl_map(function(act)
    if act.data.edit and in_selection then
      act.edit = act.data.edit(range)
    end
  end, res)

  handler(nil, res)
end
