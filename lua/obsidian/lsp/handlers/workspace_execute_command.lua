---Mostly not needed, but some lsp related plugins like nvim-cmp-lsp don't support vim.lsp.commmands yet

---@param params lsp.ExecuteCommandParams
return function(params)
  local command = params.command:gsub("obsidian%.", "")
  local actions = require "obsidian.actions"
  ---@diagnostic disable-next-line: param-type-mismatch
  local action = vim.schedule_wrap(actions[command])
  local args = params.arguments and params.arguments or {}
  ---@diagnostic disable-next-line: param-type-mismatch
  pcall(action, unpack(args))
end
