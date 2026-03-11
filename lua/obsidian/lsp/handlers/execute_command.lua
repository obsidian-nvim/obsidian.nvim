local NewNoteSourceBase = require "obsidian.completion.sources.base.new"
local log = require "obsidian.log"

---@param params lsp.ExecuteCommandParams
---@param callback fun(err: any, result: any)
return function(params, callback, _)
  if params.command == "obsidian.create_note" then
    local args = params.arguments or {}
    local item = args[1]
    if not item then
      callback("obsidian.create_note: missing item argument", nil)
      return
    end

    local source = NewNoteSourceBase.new()
    local ok, err = pcall(source.process_execute, source, item)
    if ok then
      callback(nil, {})
    else
      log.err("obsidian.create_note failed: " .. tostring(err))
      callback(tostring(err), nil)
    end
  else
    callback("Unknown command: " .. tostring(params.command), nil)
  end
end
