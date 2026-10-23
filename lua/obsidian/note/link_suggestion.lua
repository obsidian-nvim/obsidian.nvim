local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"
local parse_tags = require "obsidian.parse.tags"
local Note = require "obsidian.note"
local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}
local symbol_index

---@class obsidian.LinkSuggestion
---@field range obsidian.Range
---@field text string
---@field candidates obsidian.LinkSuggestionCandidate[]

---@class obsidian.LinkSuggestionCandidate
---@field new_text string
---@field symbol string
---@field target_path string

---@class obsidian.LinkSuggestionSymbol
---@field text string
---@field text_lower string
---@field target_paths string[]

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

---@param symbols table<string, obsidian.LinkSuggestionSymbol>
---@param text string?
---@param target_path string
local function add_symbol(symbols, text, target_path)
  text = normalize_symbol_text(text)
  if not text then
    return
  end

  local text_lower = text:lower()
  local symbol = symbols[text_lower]
  if not symbol then
    symbols[text_lower] = {
      text = text,
      text_lower = text_lower,
      target_paths = { target_path },
    }
  elseif not vim.tbl_contains(symbol.target_paths, target_path) then
    symbol.target_paths[#symbol.target_paths + 1] = target_path
  end
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

symbol_index = require("obsidian.cache.volatile").vault_index {
  version = function(context)
    return context.generation
  end,
  build = function(context, done)
    local cache = require "obsidian.cache"
    local ok, rows = pcall(cache.notes.all)
    if not ok then
      done {}
      return
    end

    ---@type table<string, obsidian.LinkSuggestionSymbol>
    local by_text = {}
    for path, row in pairs(rows) do
      path = vim.fs.normalize(path)
      if not context.workspace or api.path_is_note(path, context.workspace) then
        add_symbol(by_text, basename(path), path)
        for _, alias in ipairs(row.aliases or {}) do
          add_symbol(by_text, alias, path)
        end
      end
    end
    done(vim.tbl_values(by_text))
  end,
}

---Build mention symbols from notes in the requested workspace.
---@param path string
---@param opts { include_current: boolean?, dir: string|obsidian.Path|? }?
---@return obsidian.LinkSuggestionSymbol[]
function M.symbols(path, opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() or not cache.is_ready() then
    return {}
  end

  local dir = opts.dir and tostring(opts.dir) or nil
  local current_path = vim.fs.normalize(path) or nil
  local all_symbols
  symbol_index:get(tostring(Obsidian.dir), {
    generation = cache.generation(),
    workspace = api.find_workspace(path),
  }, function(value)
    all_symbols = value
  end)
  if not all_symbols then
    return {}
  end

  local symbols = {}
  for _, symbol in ipairs(all_symbols) do
    local target_paths = {}
    for _, target_path in ipairs(symbol.target_paths) do
      if path_in_dir(target_path, dir) and (opts.include_current or target_path ~= current_path) then
        target_paths[#target_paths + 1] = target_path
      end
    end
    if #target_paths > 0 then
      table.sort(target_paths)
      symbols[#symbols + 1] = {
        text = symbol.text,
        text_lower = symbol.text_lower,
        target_paths = target_paths,
      }
    end
  end

  table.sort(symbols, function(a, b)
    if #a.text ~= #b.text then
      return #a.text > #b.text
    end
    return a.text_lower < b.text_lower
  end)
  return symbols
end

---Return symbols that resolve only to the requested note path.
---@param path string
---@param opts { dir: string|obsidian.Path|? }?
---@return obsidian.LinkSuggestionSymbol[]
function M.symbols_for_path(path, opts)
  local normalized_path = vim.fs.normalize(path)
  local symbols = M.symbols(path, { include_current = true, dir = opts and opts.dir })
  local matching_symbols = {}
  for _, symbol in ipairs(symbols) do
    if vim.tbl_contains(symbol.target_paths, normalized_path) then
      matching_symbols[#matching_symbols + 1] = vim.tbl_extend("force", {}, symbol, {
        target_paths = { normalized_path },
      })
    end
  end
  return matching_symbols
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

  for _, ref in ipairs(parse_refs.extract(line, { row = row, lexical = true })) do
    if ref.kind == "wiki" or ref.kind == "markdown" then
      ranges[#ranges + 1] = ref.range
    end
  end
  for _, tag in ipairs(parse_tags.extract(line, { row = row, lexical = true })) do
    ranges[#ranges + 1] = tag.range
  end

  -- Markdown autolinks like <https://example.com/foo>.
  add_pattern_ranges(ranges, line, row, "<[%a][%w+.-]*://[^>%s]+>")
  -- Bare URLs. These are intentionally broad; trailing punctuation is harmless
  -- here because skipped ranges only suppress link suggestions.
  add_pattern_ranges(ranges, line, row, "[%a][%w+.-]*://%S+")

  return ranges
end

---@param line string
---@param row integer 1-indexed row number
---@param symbols obsidian.LinkSuggestionSymbol[]
---@param path_exists fun(path: string): boolean|nil
---@param source_dir string|obsidian.Path|nil
---@param document obsidian.parse.Document|nil
function M.find_in_line(line, row, symbols, path_exists, source_dir, document)
  path_exists = path_exists or function(path)
    return vim.uv.fs_stat(path) ~= nil
  end
  ---@type obsidian.LinkSuggestion[]
  local suggestions = {}
  local row0 = row - 1

  local skip_ranges = skipped_inline_ranges(line, row0)
  local line_lower = line:lower()
  local local_document = document == nil and Document.parse { line } or nil

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
      local candidate_range = Range.new(row0, start0, row0, end0)
      local excluded
      if document then
        excluded = document:intersects(candidate_range, Document.BODY_EXCLUSIONS)
      else
        excluded = assert(local_document, "local document is missing"):intersects(
          Range.new(0, start0, 0, end0),
          Document.BODY_EXCLUSIONS
        )
      end
      if
        not excluded
        and boundary_ok(line, start0, end0, symbol.text)
        and not overlaps_ranges(skip_ranges, row0, start0, end0)
        and not overlaps_existing_suggestion(suggestions, row0, start0, end0)
      then
        local target_paths = vim.tbl_filter(path_exists, symbol.target_paths)
        local label = line:sub(start_col, end_col)
        local candidates = {}
        for _, path in ipairs(target_paths) do
          local ok_link, new_text = pcall(function()
            return Note.new(basename(path), nil, nil, path):format_link {
              label = label,
              format = #target_paths > 1 and "absolute" or nil,
              dir = source_dir,
            }
          end)

          if ok_link then
            candidates[#candidates + 1] = {
              new_text = new_text,
              symbol = symbol.text,
              target_path = path,
            }
          end
        end

        if #candidates > 0 then
          suggestions[#suggestions + 1] = {
            range = candidate_range,
            text = label,
            candidates = candidates,
          }
        end
      end

      search_start = end_col + 1
    end
  end
  return suggestions
end

---@param note obsidian.Note
---@param opts { include_current: boolean?, range: obsidian.Range? }?
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
  local document = Document.parse(note.raw_contents or note.contents)

  local body_first = document.frontmatter and document.frontmatter.range.end_row + 1 or 1
  local start_line = opts.range and math.max(body_first, opts.range.start_row + 1) or body_first
  local end_line = #note.contents
  if opts.range then
    end_line = math.min(end_line, opts.range["end_row"] + (opts.range.end_col > 0 and 1 or 0))
  end
  ---@cast end_line integer
  local path_status = {}
  local source_dir = vim.fs.dirname(current_path)
  local function path_exists(path)
    if path_status[path] == nil then
      path_status[path] = vim.uv.fs_stat(path) ~= nil
    end
    return path_status[path]
  end
  for row = start_line, end_line do
    local line = note.contents[row]
    ---@cast line string
    local results = M.find_in_line(line, row, symbols, path_exists, source_dir, document)
    vim.list_extend(suggestions, results)
  end

  table.sort(suggestions, function(a, b)
    if a.range.start_row ~= b.range.start_row then
      return a.range.start_row < b.range.start_row
    end
    if a.range.start_col ~= b.range.start_col then
      return a.range.start_col < b.range.start_col
    end
    return a.text < b.text
  end)

  return suggestions
end

---Apply a link suggestion candidate to a buffer.
---@param bufnr integer
---@param suggestion obsidian.LinkSuggestion
---@param candidate obsidian.LinkSuggestionCandidate
function M.apply(bufnr, suggestion, candidate)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local range = suggestion.range
  local current_text =
    vim.api.nvim_buf_get_text(bufnr, range.start_row, range.start_col, range.end_row, range.end_col, {})
  if #current_text ~= 1 or current_text[1] ~= suggestion.text then
    return log.warn "Link suggestion is no longer current"
  end

  require("obsidian.link").replace { bufnr = bufnr, range = range, text = candidate.new_text }
  require("obsidian.ui").update(bufnr)
end

---Apply a link suggestion candidate to a possibly unloaded file, writing it to disk.
---@param path string
---@param suggestion obsidian.LinkSuggestion
---@param candidate obsidian.LinkSuggestionCandidate
function M.apply_to_file(path, suggestion, candidate)
  local bufnr = vim.fn.bufnr(path)
  local was_loaded = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
  if bufnr < 1 then
    bufnr = vim.fn.bufadd(path)
  end
  vim.fn.bufload(bufnr)

  M.apply(bufnr, suggestion, candidate)
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd "write"
  end)

  -- Do not pollute the buffer list with files that were not open before.
  if not was_loaded then
    vim.api.nvim_buf_delete(bufnr, { unload = true })
  end
end

return M
