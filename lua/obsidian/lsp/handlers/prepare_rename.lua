local rename = require "obsidian.lsp.handlers._rename"

--- Answer with the element under the cursor, or nothing ("Nothing to rename").
---@param params lsp.PrepareRenameParams|?
return function(params, handler)
  local bufnr, position = rename.resolve_params(params)
  local target = rename.target_at(bufnr, position)

  handler(nil, target and { range = target.range, placeholder = target.placeholder } or nil)
end
