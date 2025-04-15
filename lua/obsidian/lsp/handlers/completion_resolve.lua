local util = require "obsidian.lsp.util"

---@param _ obsidian.Client
---@param params table
---@param handler function
return function(_, params, handler, _)
  local kind = params.data.kind

  if kind == "ref" then
    local content = util.read_file(params.data.file)
    if content then
      params.documentation = {
        value = content,
        kind = "markdown",
      }
      handler(nil, params)
    else
      vim.notify("No notes found", 3)
    end
  end
end
