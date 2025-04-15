local M = {}
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

local link_query = [[
(
  (inline_link
    (link_text) @text
    (link_destination) @url
  ) @link
 )
(
  (reference_link
    (link_text) @text
    (link_reference) @url
  ) @link
 )
]]

---Extract headings from buffer
---@param client obsidian.Client
---@param bufnr integer
---@return table TODO:
M.get_headings = function(client, bufnr)
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

---@param client obsidian.Client
---@param bufnr integer
---@param lsp.DocumentLink[]
M.get_links = function(client, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local links = {}
  local lang = ts.language.get_lang(vim.bo[bufnr].filetype)

  -- Tree-sitter part for Markdown links
  if lang then
    local parser = ts.get_parser(bufnr, lang)
    if parser then
      local query_success, query = pcall(ts.query.parse, lang, link_query)

      if query_success and query then
        local root = parser:parse()[1]:root()
        for _, match, _ in query:iter_matches(root, bufnr) do
          local link_info = {}
          for id, node in pairs(match) do
            local capture_name = query.captures[id]
            if capture_name == "text" then
              link_info.text = ts.get_node_text(node, bufnr)
            elseif capture_name == "url" then
              link_info.url = ts.get_node_text(node, bufnr)
            elseif capture_name == "link" then
              local start_row, start_col = node:start()
              link_info.line = start_row
              link_info.column = start_col
            end
          end
          if link_info.text and link_info.url then
            table.insert(links, {
              text = link_info.text,
              url = link_info.url,
              line = link_info.line,
              column = link_info.column,
              type = "markdown",
            })
          end
        end
      end
    end
  end

  -- Regex part for wiki-style links [[...]]
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for line_idx, line in ipairs(lines) do
    local col = 0
    while true do
      local start, end_ = line:find("%[%[.-%]%]", col)
      if not start then
        break
      end

      local content = line:sub(start + 2, end_ - 2)
      local target, text = content:match "^([^|]*)%|?(.*)$"
      text = text ~= "" and text or target

      table.insert(links, {
        kind = 15,
        target = target, -- TODO: resolve to path
        range = {
          start = { line = line_idx - 1, character = 1 },
          ["end"] = { line = line_idx - 1, character = 1 },
        },
      })

      col = end_ + 1
    end
  end

  return links
end

-- TODO: make async in the future?

function M.read_file(file)
  local fd = assert(io.open(file, "r"))
  ---@type string
  local data = fd:read "*a"
  fd:close()
  return data
end

return M
