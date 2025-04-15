local ts = vim.treesitter

local heading_query = [[
    (setext_heading
      heading_content: (_) @h1
      (setext_h1_underline))
    (setext_heading
      heading_content: (_) @h2
      (setext_h2_underline))
    (atx_heading
      (atx_h1_marker)
      heading_content: (_) @h1)
    (atx_heading
      (atx_h2_marker)
      heading_content: (_) @h2)
    (atx_heading
      (atx_h3_marker)
      heading_content: (_) @h3)
    (atx_heading
      (atx_h4_marker)
      heading_content: (_) @h4)
    (atx_heading
      (atx_h5_marker)
      heading_content: (_) @h5)
    (atx_heading
      (atx_h6_marker)
      heading_content: (_) @h6)
  ]]

return function(_, params, handler)
  --- Extract headings from buffer
  --- @param bufnr integer buffer to extract headings from
  --- @return table TODO:
  local get_headings = function(bufnr)
    local lang = ts.language.get_lang(vim.bo[bufnr].filetype)
    if not lang then
      return {}
    end
    local parser = assert(ts.get_parser(bufnr, lang, { error = false }))
    local query = ts.query.parse(lang, heading_query)
    local root = parser:parse()[1]:root()
    local headings = {}
    for id, node, _, _ in query:iter_captures(root, bufnr) do
      local text = string.rep("#", id) .. " " .. ts.get_node_text(node, bufnr)
      local row, _ = node:start()
      table.insert(headings, {
        kind = 15,
        range = {
          start = { line = row, character = 1 },
          ["end"] = { line = row, character = 1 },
        },
        selectionRange = {
          start = { line = row, character = 1 },
          ["end"] = { line = row, character = 1 },
        },
        name = text,
      })
    end
    return headings
  end

  local bufnr = vim.uri_to_bufnr(params.textDocument.uri)
  handler(nil, get_headings(bufnr))
end
