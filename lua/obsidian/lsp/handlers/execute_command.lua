---@param params lsp.ExecuteCommandParams
return function(params)
  local cmd = params.command
  local action = require("obsidian.lsp.handlers._code_action").actions[cmd]
  pcall(action.data.fn)
end
