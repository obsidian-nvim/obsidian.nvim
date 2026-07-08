local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"
local log = require "obsidian.log"
local Note = require "obsidian.note"

local M = {}

---@class obsidian.LinkSuggestionSymbol
---@field text string
---@field text_lower string
---@field target_path string
---@field target_name string

---@class obsidian.LinkSuggestion
---@field range obsidian.Range
---@field text string
---@field new_text string
---@field symbol string
---@field target_path string
---@field target_name string

---@param path string
---@return string
local function basename(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

---@param s any
---@return string?
local function normalize_symbol_text(s)
  if type(s) ~= "string" then
    return nil
  end
  s = vim.trim(s)
  if s == "" then
    return nil
  end
  return s
end

---@param symbols obsidian.LinkSuggestionSymbol[]
---@param seen table<string, boolean>
---@param text string?
---@param target_path string
---@param target_name string
---@param kind "stem"|"alias"
local function add_symbol(symbols, seen, text, target_path, target_name, kind)
  text = normalize_symbol_text(text)
  if not text then
    return
  end

  local key = target_path .. "\0" .. text:lower()
  if seen[key] then
    return
  end
  seen[key] = true

  symbols[#symbols + 1] = {
    text = text,
    text_lower = text:lower(),
    target_path = target_path,
    target_name = target_name,
    kind = kind,
  }
end

---Build mention symbols from the note cache.
---@param opts { current_path: string|?, include_current: boolean? }?
---@return obsidian.LinkSuggestionSymbol[]
function M.symbols(opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    return {}
  end

  local ok, rows = pcall(cache.notes.all)
  if not ok then
    return {}
  end

  local current_path = opts.current_path and vim.fs.normalize(opts.current_path) or nil
  local symbols = {}
  local seen = {}

  for path, row in pairs(rows) do
    path = vim.fs.normalize(path)
    if opts.include_current or path ~= current_path then
      local name = basename(path)
      add_symbol(symbols, seen, name, path, name, "stem")
      for _, alias in ipairs(row.aliases or {}) do
        add_symbol(symbols, seen, alias, path, name, "alias")
      end
    end
  end

  table.sort(symbols, function(a, b)
    if #a.text ~= #b.text then
      return #a.text > #b.text
    end
    return a.text < b.text
  end)

  return symbols
end

---@param byte integer?
---@return boolean
local function is_ascii_word_byte(byte)
  return byte ~= nil
    and ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95)
end

---@param s string
---@return boolean
local function starts_or_ends_with_ascii_word(s)
  return is_ascii_word_byte(s:byte(1)) or is_ascii_word_byte(s:byte(#s))
end

---@param line string
---@param start_col integer 0-based, inclusive
---@param end_col integer 0-based, exclusive
---@param symbol string
---@return boolean
local function boundary_ok(line, start_col, end_col, symbol)
  if not starts_or_ends_with_ascii_word(symbol) then
    return true
  end

  local before = start_col > 0 and line:byte(start_col) or nil
  local after = end_col < #line and line:byte(end_col + 1) or nil
  return not is_ascii_word_byte(before) and not is_ascii_word_byte(after)
end

---@param ranges obsidian.Range[]
---@param row integer
---@param start_col integer
---@param end_col integer
---@return boolean
local function overlaps_ranges(ranges, row, start_col, end_col)
  for _, range in ipairs(ranges) do
    if range.start_row == row and start_col < range.end_col and end_col > range.start_col then
      return true
    end
  end
  return false
end

---@param suggestions obsidian.LinkSuggestion[]
---@param row integer
---@param start_col integer
---@param end_col integer
---@return boolean
local function overlaps_existing_suggestion(suggestions, row, start_col, end_col)
  for _, suggestion in ipairs(suggestions) do
    local range = suggestion.range
    if range.start_row == row and start_col < range.end_col and end_col > range.start_col then
      return not (start_col == range.start_col and end_col == range.end_col)
    end
  end
  return false
end

---@param ranges obsidian.Range[]
---@param line string
---@param row integer
---@param pattern string
local function add_pattern_ranges(ranges, line, row, pattern)
  local search_start = 1
  while search_start <= #line do
    local start_col, end_col = line:find(pattern, search_start)
    if not start_col or not end_col then
      break
    end
    ranges[#ranges + 1] = Range.new(row, start_col - 1, row, end_col)
    search_start = end_col + 1
  end
end

---@param line string
---@param row integer
---@return obsidian.Range[]
local function skipped_inline_ranges(line, row)
  local ranges = {}

  for _, ref in ipairs(parse_refs.extract(line, { row = row })) do
    if ref.kind == "wiki" or ref.kind == "markdown" then
      ranges[#ranges + 1] = ref.range
    end
  end

  add_pattern_ranges(ranges, line, row, "`[^`]*`")
  -- Markdown autolinks like <https://example.com/foo>.
  add_pattern_ranges(ranges, line, row, "<[%a][%w+.-]*://[^>%s]+>")
  -- Bare URLs. These are intentionally broad; trailing punctuation is harmless
  -- here because skipped ranges only suppress link suggestions.
  add_pattern_ranges(ranges, line, row, "[%a][%w+.-]*://%S+")

  return ranges
end

---@param lines string[]
---@return integer frontmatter_end_row 0-based exclusive end row, 0 if none
local function frontmatter_end_row(lines)
  if lines[1] ~= "---" then
    return 0
  end
  for i = 2, #lines do
    if lines[i] == "---" or lines[i] == "..." then
      return i
    end
  end
  return 0
end

---@param lines string[]
---@param opts { current_path: string|?, include_current: boolean?, symbols: obsidian.LinkSuggestionSymbol[]? }?
---@return obsidian.LinkSuggestion[]
function M.find(lines, opts)
  opts = opts or {}
  local symbols = opts.symbols or M.symbols { current_path = opts.current_path, include_current = opts.include_current }
  if #symbols == 0 or #lines == 0 then
    return {}
  end

  local suggestions = {}
  local fm_end = frontmatter_end_row(lines)
  local in_code_block = false

  for row, line in ipairs(lines) do
    local row0 = row - 1
    local search_line = row > fm_end and not in_code_block

    if line:match "^%s*```" then
      in_code_block = not in_code_block
      search_line = false
    end

    if search_line then
      local skip_ranges = skipped_inline_ranges(line, row0)
      local line_lower = line:lower()

      for _, symbol in ipairs(symbols) do
        local search_start = 1
        while search_start <= #line do
          local start_col, end_col = line_lower:find(symbol.text_lower, search_start, true)
          if not start_col or not end_col then
            break
          end

          ---@cast start_col integer
          ---@cast end_col integer
          local start0 = start_col - 1
          local end0 = end_col
          if
            boundary_ok(line, start0, end0, symbol.text)
            and not overlaps_ranges(skip_ranges, row0, start0, end0)
            and not overlaps_existing_suggestion(suggestions, row0, start0, end0)
          then
            suggestions[#suggestions + 1] = {
              range = Range.new(row0, start0, row0, end0),
              text = line:sub(start_col, end_col),
              new_text = Note.from_file(symbol.target_path):format_link {
                label = line:sub(start_col, end_col),
              },
              symbol = symbol.text,
              target_path = symbol.target_path,
              target_name = symbol.target_name,
            }
          end

          search_start = end_col + 1
        end
      end
    end
  end

  table.sort(suggestions, function(a, b)
    if a.range.start_row ~= b.range.start_row then
      return a.range.start_row < b.range.start_row
    end
    if a.range.start_col ~= b.range.start_col then
      return a.range.start_col < b.range.start_col
    end
    return a.target_name < b.target_name
  end)

  return suggestions
end

---@param bufnr integer
---@param opts { current_path: string|?, include_current: boolean? }?
---@return obsidian.LinkSuggestion[]
function M.find_buffer(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  opts.current_path = opts.current_path or vim.api.nvim_buf_get_name(bufnr)
  return M.find(lines, opts)
end

---@param suggestion obsidian.LinkSuggestion
---@param row integer
---@param col integer 0-based byte index
---@return boolean
local function contains_cursor(suggestion, row, col)
  local range = suggestion.range
  return range.start_row == row and range.start_col <= col and col <= range.end_col
end

---@param bufnr integer?
---@param win integer?
---@return obsidian.LinkSuggestion[]
function M.at_cursor(bufnr, win)
  bufnr = bufnr or 0
  win = win or 0
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row = cursor[1] - 1
  local col = cursor[2]
  local out = {}

  for _, suggestion in ipairs(M.find_buffer(bufnr)) do
    if contains_cursor(suggestion, row, col) then
      out[#out + 1] = suggestion
    end
  end

  return out
end

---@param suggestion obsidian.LinkSuggestion
---@param filename string
---@return obsidian.PickerEntry
local function picker_entry(suggestion, filename)
  local line = suggestion.range.start_row + 1
  local col = suggestion.range.start_col + 1

  return {
    filename = filename,
    lnum = line,
    col = col,
    end_lnum = suggestion.range.end_row + 1,
    end_col = suggestion.range.end_col + 1,
    text = string.format("%s -> %s", suggestion.text, suggestion.new_text),
    user_data = suggestion,
  }
end

---@param entry obsidian.PickerEntry
---@return string
local function format_entry(entry)
  return entry.text or ""
end

---@param bufnr integer
---@param suggestion obsidian.LinkSuggestion
function M.apply(bufnr, suggestion)
  bufnr = bufnr or 0
  local range = suggestion.range
  local lines = vim.api.nvim_buf_get_text(bufnr, range.start_row, range.start_col, range.end_row, range.end_col, {})
  local current_text = table.concat(lines, "\n")
  if current_text == "" then
    current_text = suggestion.text
  end

  vim.api.nvim_buf_set_text(
    bufnr,
    range.start_row,
    range.start_col,
    range.end_row,
    range.end_col,
    { suggestion.new_text }
  )
  require("obsidian.ui").update(bufnr)
end

---@param bufnr integer?
function M.pick(bufnr)
  bufnr = bufnr or 0
  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    log.warn "Link suggestions require the Obsidian cache"
    return
  end

  local function open_picker()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local entries = vim.tbl_map(function(suggestion)
      return picker_entry(suggestion, filename)
    end, M.find_buffer(bufnr))

    if #entries == 0 then
      log.warn "No unlinked mentions found"
      return
    end

    Obsidian.picker.pick(entries, {
      prompt_title = "Unlinked mentions",
      format_item = format_entry,
      callback = function(entry)
        local suggestion = entry.user_data
        if suggestion then
          M.apply(bufnr, suggestion)
        end
      end,
    })
  end

  if cache.is_ready() then
    open_picker()
  else
    cache.when_ready(open_picker)
  end
end

return M
