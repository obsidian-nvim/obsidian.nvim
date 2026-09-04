local Range = require "obsidian.range"

---@param _ lsp.DocumentLinkParams
return function(_, handler)
  local path, range = require("obsidian.link").includeexpr()

  if path and range then
    ---@type lsp.DocumentLink[]
    local res = {
      {
        range = Range.to_lsp(range),
        target = vim.uri_from_fname(path),
      },
    }
    handler(nil, res)
  end
end
