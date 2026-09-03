local api = require "obsidian.api"
local link_suggestion = require "obsidian.note.link_suggestion"

local M = {}

local MAX_SYMBOLS = 10

---@param bufnr integer
---@param text string
---@return string
local function keyword_suffix(bufnr, text)
  return vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.matchstr(text, [[\k\+$]])
  end)
end

---@param before string
---@param start_col integer
---@return boolean
local function is_explicit_completion(before, start_col)
  local leading = before:sub(1, start_col)
  local trailing_token = before:match "%S+$" or ""
  return leading:match "%[%[[^%]]*$" ~= nil or leading:match "%[%^[^%]]*$" ~= nil or trailing_token:sub(1, 1) == "#"
end

---@param ctx obsidian.resolver.InlineCompletionCtx
---@return lsp.InlineCompletionItem[]
function M.complete(ctx)
  local note = ctx.note
  local path = note.path and tostring(note.path) or nil
  local position = ctx.position
  if not path or not position then
    return {}
  end

  -- Keep inline completion out of frontmatter. Existing completion sources
  -- already handle structured tag values there.
  if note.frontmatter_end_line and position.line < note.frontmatter_end_line then
    return {}
  end

  local line = note.contents[position.line + 1]
  if not line or position.character > #line then
    return {}
  end

  local before = line:sub(1, position.character)
  local query = keyword_suffix(ctx.bufnr, before)
  if query == "" or #query < Obsidian.opts.completion.min_chars then
    return {}
  end

  local start_col = position.character - #query
  if is_explicit_completion(before, start_col) then
    return {}
  end

  local workspace_dir = api.resolve_workspace_dir(path)
  local symbols = link_suggestion.symbols(path, { dir = workspace_dir })
  local query_lower = query:lower()
  local matching = vim.tbl_filter(function(symbol)
    return vim.startswith(symbol.text_lower, query_lower)
  end, symbols)
  table.sort(matching, function(a, b)
    local a_exact = a.text_lower == query_lower
    local b_exact = b.text_lower == query_lower
    if a_exact ~= b_exact then
      return a_exact
    elseif #a.text ~= #b.text then
      return #a.text < #b.text
    end
    return a.text_lower < b.text_lower
  end)

  local range = {
    start = { line = position.line, character = start_col },
    ["end"] = { line = position.line, character = position.character },
  }
  local source_dir = vim.fs.dirname(path)
  local seen = {}
  local items = {}

  local function add(insert_text)
    if seen[insert_text] then
      return
    end
    seen[insert_text] = true
    items[#items + 1] = {
      insertText = insert_text,
      filterText = query,
      range = range,
    }
  end

  for i, symbol in ipairs(matching) do
    if i > MAX_SYMBOLS then
      break
    end

    -- An exact plain candidate would render no virtual text and obscure the
    -- useful link candidate, so omit it unless it changes the spelling/case.
    if symbol.text ~= query then
      add(symbol.text)
    end
    for _, candidate in ipairs(link_suggestion.link_candidates(symbol, symbol.text, source_dir)) do
      add(candidate.new_text)
    end
  end

  return items
end

return M
