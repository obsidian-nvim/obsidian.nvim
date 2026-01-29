---@param params lsp.ExecuteCommandParams
return function(params)
  local cmd = params.command
  local fn = require("obsidian.actions")[cmd]
  pcall(fn)
end
