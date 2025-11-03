---@param params lsp.ExecuteCommandParams
return function(params)
  local cmd = params.command

  local ok, fn = pcall(require, "obsidian.lsp.commands." .. cmd)
  if ok and fn then
    fn()
  end
  -- return require("obsidian.lsp.handlers.commands." .. cmd)(client, params)
  -- return require "obsidian.lsp.handlers.commands.createNote"(client, params)
end
