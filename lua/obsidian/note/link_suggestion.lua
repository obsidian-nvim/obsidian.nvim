local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"
local Note = require "obsidian.note"
local api = require "obsidian.api"

local M = {}

---@class obsidian.LinkSuggestionSymbol
---@field text string
---@field text_lower string
---@field target_path string
---@field target_name string
---@field kind "stem"|"alias"

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

---@param path string
---@param dir string?
---@return boolean
local function path_in_dir(path, dir)
  if not dir then
    return true
  end

  dir = vim.fs.normalize(dir):gsub("/+$", "")
  path = vim.fs.normalize(path)
  return path == dir or vim.startswith(path, dir .. "/")
end

---Build mention symbols from notes in the requested workspace.
---@param path string
---@param opts { include_current: boolean?, dir: string|obsidian.Path|? }?
---@return obsidian.LinkSuggestionSymbol[]
function M.symbols(path, opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() then
    return {}
  end

  local dir = opts.dir and tostring(opts.dir) or nil
  local current_path = vim.fs.normalize(path) or nil
  local rows = {}
  local ok, cached_rows = pcall(cache.notes.all)
  if ok then
    for p, row in pairs(cached_rows) do
      p = vim.fs.normalize(p)
      if path_in_dir(p, dir) and vim.uv.fs_stat(p) then
        rows[p] = row
      end
    end
  end

  -- local has_symbol_source = false
  -- for p, _ in pairs(rows) do
  --   if opts.include_current or vim.fs.normalize(p) ~= current_path then
  --     has_symbol_source = true
  --     break
  --   end
  -- end

  -- -- The cache is currently scoped to the active workspace. If this buffer belongs
  -- -- to a different workspace, build symbols by scanning that workspace instead of
  -- -- falling back to Obsidian.workspace.
  -- if dir and not has_symbol_source then
  --   rows = scan_rows(dir)
  -- end

  local symbols = {}
  local seen = {}

  for p, row in pairs(rows) do
    p = vim.fs.normalize(p)
    if opts.include_current or p ~= current_path then
      local name = basename(p)
      add_symbol(symbols, seen, name, p, name, "stem")
      for _, alias in ipairs(row.aliases or {}) do
        add_symbol(symbols, seen, alias, p, name, "alias")
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

---@param note obsidian.Note
---@param opts { include_current: boolean? }?
---@return obsidian.LinkSuggestion[]
function M.find(note, opts)
  opts = opts or {}
  local current_path = note.path and tostring(note.path)
  if not current_path then
    return {}
  end
  local dir = current_path and api.resolve_workspace_dir(current_path) or nil
  local symbols = M.symbols(current_path, { include_current = opts.include_current, dir = dir })
  if #symbols == 0 or #note.contents == 0 then
    return {}
  end

  local suggestions = {}
  local fm_end = note.frontmatter_end_line or 0
  local in_code_block = false

  for row, line in ipairs(note.contents) do
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
            local label = line:sub(start_col, end_col)
            local ok_link, new_text = pcall(function()
              return Note.new(symbol.target_name, nil, nil, symbol.target_path):format_link {
                label = label,
                format = "absolute",
              }
            end)

            if ok_link then
              suggestions[#suggestions + 1] = {
                range = Range.new(row0, start0, row0, end0),
                text = label,
                new_text = new_text,
                symbol = symbol.text,
                target_path = symbol.target_path,
                target_name = symbol.target_name,
              }
            end
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

return M
