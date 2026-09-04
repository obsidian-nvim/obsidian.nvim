local Range = require "obsidian.range"
local link = require "obsidian.link"
local parse_refs = require "obsidian.parse.refs"

---@param params lsp.DocumentLinkParams
---@param handler fun(_: any, res: lsp.DocumentLink[])
return function(params, handler)
  local fname = vim.uri_to_fname(params.textDocument.uri)
  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)

  local lines
  if bufnr ~= 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  else
    local f = io.open(fname, "r")
    if not f then
      return handler(nil, {})
    end
    lines = {}
    for line in f:lines() do
      lines[#lines + 1] = line
    end
    f:close()
  end

  ---@type lsp.DocumentLink[]
  local res = {}
  for i, line in ipairs(lines) do
    for _, ref in ipairs(parse_refs.extract(line, { row = i - 1 })) do
      -- Footnotes reference in-file definitions, not documents.
      if ref.kind ~= "footnote" then
        local location = ref.target
        local decoded = vim.uri_decode(location)
        if decoded then
          ---@cast decoded string
          location = decoded
        end
        local path = link.resolve_link_path(location, fname)
        if path then
          res[#res + 1] = {
            range = Range.to_lsp(ref.range),
            target = vim.uri_from_fname(path),
          }
        end
      end
    end
  end

  handler(nil, res)
end
