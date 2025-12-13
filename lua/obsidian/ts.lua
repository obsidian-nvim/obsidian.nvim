local query = vim.treesitter.query
local Range = require "vim.treesitter._range"
local get_text = vim.treesitter.get_node_text

local function parse_inline(node, src)
  local inline_parser = vim.treesitter.get_string_parser(src, "markdown_inline")
  local inline_query = vim.treesitter.query.get("markdown_inline", "highlights")
  assert(inline_query) -- TODO: proper return if nil

  local res = {}

  local child_range = { node:range() }

  local inline_tree = inline_parser:parse(child_range)[1]

  for id, n, metadata in inline_query:iter_captures(inline_tree:root(), src) do
    local name = inline_query.captures[id]
    local hl = "@" .. name .. "." .. "markdown_inline"
    if name ~= "conceal" then
      return { get_text(node, src), hl }
    end
  end
end

-- ---@package
-- ---@param capture integer
-- ---@return integer?
-- function TSHighlighterQuery:get_hl_from_capture(capture)
--   if not self.hl_cache[capture] then
--     local name = self._query.captures[capture]
--     local id = 0
--     if not vim.startswith(name, '_') then
--       id = api.nvim_get_hl_id_by_name('@' .. name .. '.' .. self.lang)
--     end
--     self.hl_cache[capture] = id
--   end
--
--   return self.hl_cache[capture]
-- end

---@param langtree vim.treesitter.LanguageTree
---@param src integer|string|?
---@return table<integer, table[]> line_spans
local function collect_ts_highlight_lines(langtree, src)
  local lines = {}

  local tree = langtree:parse()[1]
  local root = tree:root()

  local query = vim.treesitter.query.get("markdown", "highlights")

  ---@param node TSNode
  local function trav(node)
    for child in node:iter_children() do
      if child:child_count() > 0 then
        trav(child)
      end
      if child:type() == "inline" then
        parse_inline(child, src)
      end
    end
  end

  trav(root)

  return lines
end

local function buf_to_virt_lines(buf)
  local parser = vim.treesitter.get_parser(buf)
  assert(parser)

  local spans_by_line = collect_ts_highlight_lines(parser, buf)

  local virt_lines = {}

  for row, spans in pairs(spans_by_line) do
    local virt = {}
    local col = 0

    for _, s in ipairs(spans) do
      if s.col_start > col then
        table.insert(virt, { string.rep(" ", s.col_start - col), nil })
      end
      table.insert(virt, { s.text, s.hl_group })
      col = s.col_end
    end

    virt_lines[row] = virt
  end
  return virt_lines
end

return {
  buf_to_virt_lines = buf_to_virt_lines,
  collect_ts_highlight_lines = collect_ts_highlight_lines,
}
