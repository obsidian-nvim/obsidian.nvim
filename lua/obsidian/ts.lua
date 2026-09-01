local M = {}

local TS_PRIORITY = vim.hl and vim.hl.priorities and vim.hl.priorities.treesitter or 100
local NON_VISUAL_CAPTURES = {
  conceal = true,
  noconceal = true,
  nospell = true,
  spell = true,
}

---@class obsidian.ts.Span
---@field col_start integer
---@field col_end integer
---@field hl_group string|?
---@field priority number
---@field tree_order integer
---@field order integer
---@field conceal boolean|string|nil

---@param source integer|string
---@return string[]
local function source_lines(source)
  if type(source) == "number" then
    return vim.api.nvim_buf_get_lines(source, 0, -1, false)
  end
  return vim.split(source, "\n", { plain = true })
end

---@param metadata vim.treesitter.query.TSMetadata
---@param capture integer
---@param name string
---@param lang string
---@return string|nil hl_group
---@return boolean|string|nil conceal
---@return number priority
local function capture_attributes(metadata, capture, name, lang)
  local capture_metadata = metadata[capture] or {}
  local conceal = metadata.conceal
  if conceal == nil then
    conceal = capture_metadata.conceal
  end

  local priority = tonumber(metadata.priority or capture_metadata.priority) or TS_PRIORITY
  local hl_group
  if not NON_VISUAL_CAPTURES[name] and not vim.startswith(name, "_") then
    hl_group = "@" .. name .. "." .. lang
  end

  return hl_group, conceal, priority
end

---@param spans_by_line table<integer, obsidian.ts.Span[]>
---@param lines string[]
---@param range Range6
---@param attributes { hl_group: string|nil, priority: number, tree_order: integer, order: integer, conceal: boolean|string|nil }
local function add_range(spans_by_line, lines, range, attributes)
  local start_row, start_col, end_row, end_col = range[1], range[2], range[4], range[5]

  for row = start_row, end_row do
    local line = lines[row + 1]
    if line == nil then
      break
    end

    local col_start = row == start_row and start_col or 0
    local col_end = row == end_row and end_col or #line
    col_start = math.min(col_start, #line)
    col_end = math.min(col_end, #line)

    if col_start < col_end then
      spans_by_line[row + 1][#spans_by_line[row + 1] + 1] = {
        col_start = col_start,
        col_end = col_end,
        hl_group = attributes.hl_group,
        priority = attributes.priority,
        tree_order = attributes.tree_order,
        order = attributes.order,
        conceal = attributes.conceal,
      }
    end
  end
end

---Collect highlight-query captures from a parser, including injected languages.
---@param parser vim.treesitter.LanguageTree
---@param source integer|string
---@return table<integer, obsidian.ts.Span[]> spans_by_line
M.collect_ts_highlight_lines = function(parser, source)
  local lines = source_lines(source)
  local spans_by_line = {}
  for row = 1, #lines do
    spans_by_line[row] = {}
  end

  parser:parse(true)

  local tree_order = 0
  local capture_order = 0
  parser:for_each_tree(function(tree, langtree)
    tree_order = tree_order + 1
    local lang = langtree:lang()
    local highlight_query = vim.treesitter.query.get(lang, "highlights")
    if not highlight_query then
      return
    end

    for id, node, metadata in highlight_query:iter_captures(tree:root(), source) do
      local name = highlight_query.captures[id]
      if name then
        local hl_group, conceal, priority = capture_attributes(metadata, id, name, lang)
        if hl_group ~= nil or conceal ~= nil then
          capture_order = capture_order + 1
          local range = vim.treesitter.get_range(node, source, metadata[id])
          add_range(spans_by_line, lines, range, {
            hl_group = hl_group,
            priority = priority,
            tree_order = tree_order,
            order = capture_order,
            conceal = conceal,
          })
        end
      end
    end
  end)

  return spans_by_line
end

---@param left string|string[]|nil
---@param right string|string[]|nil
---@return boolean
local function same_highlight(left, right)
  return vim.deep_equal(left, right)
end

---@param chunks table[]
---@param text string
---@param hl_group string|string[]|nil
local function add_chunk(chunks, text, hl_group)
  if text == "" then
    return
  end

  local previous = chunks[#chunks]
  if previous and same_highlight(previous[2], hl_group) then
    previous[1] = previous[1] .. text
  else
    chunks[#chunks + 1] = { text, hl_group }
  end
end

---@param left obsidian.ts.Span
---@param right obsidian.ts.Span
---@return boolean
local function span_precedes(left, right)
  if left.priority ~= right.priority then
    return left.priority < right.priority
  elseif left.tree_order ~= right.tree_order then
    return left.tree_order < right.tree_order
  else
    return left.order < right.order
  end
end

---@param spans obsidian.ts.Span[]
---@param col_start integer
---@param col_end integer
---@return obsidian.ts.Span[]
local function active_spans(spans, col_start, col_end)
  local active = {}
  for _, span in ipairs(spans) do
    if span.col_start < col_end and span.col_end > col_start then
      active[#active + 1] = span
    end
  end
  return active
end

---@param active obsidian.ts.Span[]
---@return string|string[]|nil
local function active_highlights(active)
  local groups = {}
  local seen = {}
  for _, span in ipairs(active) do
    if span.hl_group and not seen[span.hl_group] then
      groups[#groups + 1] = span.hl_group
      seen[span.hl_group] = true
    end
  end

  if #groups == 0 then
    return nil
  elseif #groups == 1 then
    return groups[1]
  else
    return groups
  end
end

---@param active obsidian.ts.Span[]
---@return obsidian.ts.Span|nil
local function active_conceal(active)
  for i = #active, 1, -1 do
    if active[i].conceal ~= nil then
      return active[i]
    end
  end
end

---@param line string
---@param spans obsidian.ts.Span[]
---@return table[] chunks
local function line_to_chunks(line, spans)
  if line == "" then
    return {}
  end

  table.sort(spans, span_precedes)

  local boundaries = { [0] = true, [#line] = true }
  for _, span in ipairs(spans) do
    boundaries[span.col_start] = true
    boundaries[span.col_end] = true
  end

  local columns = vim.tbl_keys(boundaries)
  table.sort(columns)

  local chunks = {}
  local emitted_conceals = {}
  for i = 1, #columns - 1 do
    local col_start = columns[i]
    local col_end = columns[i + 1]
    ---@cast col_start integer
    ---@cast col_end integer
    local active = active_spans(spans, col_start, col_end)
    local conceal = active_conceal(active)
    local hl_group = active_highlights(active)

    if conceal and conceal.conceal ~= false then
      if col_start == conceal.col_start and not emitted_conceals[conceal.order] then
        emitted_conceals[conceal.order] = true
        add_chunk(chunks, type(conceal.conceal) == "string" and conceal.conceal or "", hl_group)
      end
    else
      add_chunk(chunks, line:sub(col_start + 1, col_end), hl_group)
    end
  end

  return chunks
end

---Convert source text and Tree-sitter highlight captures to virtual-line chunks.
---Falls back to unhighlighted text when the Markdown parser is unavailable.
---@param lines string[]
---@return table[] virt_lines
M.to_virt_lines = function(lines)
  local source = table.concat(lines, "\n")
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, "markdown")
  if not ok then
    return vim.tbl_map(function(line)
      return line == "" and {} or { { line } }
    end, lines)
  end

  local render_ok, spans_by_line = pcall(M.collect_ts_highlight_lines, parser, source)
  if not render_ok then
    return vim.tbl_map(function(line)
      return line == "" and {} or { { line } }
    end, lines)
  end

  local virt_lines = {}
  for row, line in ipairs(lines) do
    virt_lines[row] = line_to_chunks(line, spans_by_line[row])
  end
  return virt_lines
end

---@param buf integer
---@return table[] virt_lines
M.buf_to_virt_lines = function(buf)
  return M.to_virt_lines(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
end

return M
