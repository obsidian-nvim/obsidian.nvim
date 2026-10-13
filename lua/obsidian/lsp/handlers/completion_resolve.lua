local docs = require "obsidian.completion.docs"

--- Lazily fill in documentation for a completion item through the
--- `note_preview` resolver.
---
---@param params lsp.CompletionItem
---@param callback fun(err: any, result: lsp.CompletionItem|?)
return function(params, callback, _)
  local item = params
  if item == nil then
    callback(nil, nil)
    return
  end

  docs.resolve_item(item, function(resolved)
    callback(nil, resolved)
  end)
end
