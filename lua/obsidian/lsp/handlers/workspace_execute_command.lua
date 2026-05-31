---Mostly not needed, but some lsp related plugins like nvim-cmp-lsp don't support vim.lsp.commands yet

---@param params lsp.ExecuteCommandParams
---@param callback fun(err: lsp.ResponseError?, result: any)
return function(params, callback)
  local command = params.command:gsub("obsidian%.", "")
  local actions = require "obsidian.actions"
  if type(actions[command]) ~= "function" then
    callback({ code = -32601, message = "command not found: " .. params.command }, nil)
    return
  end

  local action = actions[command]
  local args = params.arguments and params.arguments or {}
  local ok, err = pcall(action, unpack(args))
  if ok then
    callback(nil, nil)
  else
    callback({ code = -32603, message = "command failed: " .. tostring(err) }, nil)
  end
end
