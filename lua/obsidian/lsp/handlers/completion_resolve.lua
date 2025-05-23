local util = require "obsidian.lsp.util"

---@param client obsidian.Client
---@param params lsp.CompletionItem
---@param handler fun(nil, lsp.CompletionItem)
return function(client, params, handler, _)
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
  elseif kind == "tag" then
    local content = util.preview_tag_sync(client, params, params.label)
    params.documentation = {
      value = content,
      kind = "markdown",
    }
    handler(nil, params)
  end
end
