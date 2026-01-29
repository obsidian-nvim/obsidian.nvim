---@param params lsp.ExecuteCommandParams
return function(params)
  local cmd = params.command
  local config = require("obsidian.lsp.handlers._code_action").actions_lookup[cmd]
  pcall(config.data.fn)
end
