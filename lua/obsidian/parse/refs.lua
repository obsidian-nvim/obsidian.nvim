local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local link_parser = require "obsidian.link.parser"
local uri = require "obsidian.uri"

local M = {}

---@alias obsidian.parse.RefKind "wiki"|"markdown"|"autolink"|"footnote"

---@class obsidian.parse.Ref : obsidian.parse.line.Match
---@field kind obsidian.parse.RefKind
---@field target string
---@field label string?
---@field anchor string?
---@field block string?
---@field embed boolean

---@param refs obsidian.parse.Ref[]
---@param start_col integer 1-indexed, inclusive.
---@param end_col integer 1-indexed, inclusive.
---@return boolean
local function overlaps_ref(refs, start_col, end_col)
  for _, ref in ipairs(refs) do
    local ref_start = ref.range.start_col + 1
    local ref_end = ref.range.end_col
    if (ref_start <= start_col and start_col <= ref_end) or (ref_start <= end_col and end_col <= ref_end) then
      return true
    end
  end
  return false
end

---@param line string
---@param row integer
---@param start_col integer 1-indexed, inclusive.
---@param end_col integer 1-indexed, inclusive.
---@param parser fun(raw: string, range: obsidian.Range): obsidian.parse.Ref?
---@return obsidian.parse.Ref?
local function parse_match(line, row, start_col, end_col, parser)
  if start_col > 1 and line:sub(start_col - 1, start_col - 1) == "!" then
    start_col = start_col - 1
    ---@cast start_col integer
  end

  local raw = line:sub(start_col, end_col)
  local range = Range.new(row, start_col - 1, row, end_col)
  return parser(raw, range)
end

---@param raw string
---@param range obsidian.Range
---@return obsidian.parse.Ref?
local function parse_wiki(raw, range)
  local body = raw:match "^!?%[%[(.+)%]%]$"
  if not body then
    return nil
  end

  local target, label = body, nil
  local pipe = body:find("|", 1, true)
  if pipe then
    target = body:sub(1, pipe - 1):gsub("\\$", "")
    label = body:sub(pipe + 1)
  end

  local anchor, block
  target, anchor, block = link_parser.parse(target)
  return {
    kind = "wiki",
    raw = raw,
    range = range,
    target = target,
    label = label,
    anchor = anchor,
    block = block,
    embed = raw:sub(1, 1) == "!",
  }
end

---@param raw string
---@param range obsidian.Range
---@return obsidian.parse.Ref?
local function parse_markdown(raw, range)
  local label, target = raw:match "^!?%[([^%]]*)%]%(([^%)]+)%)$"
  if not target then
    return nil
  end

  local anchor, block
  target, anchor, block = link_parser.parse(target)
  return {
    kind = "markdown",
    raw = raw,
    range = range,
    target = target,
    label = label,
    anchor = anchor,
    block = block,
    embed = raw:sub(1, 1) == "!",
  }
end

---@param raw string
---@param range obsidian.Range
---@return obsidian.parse.Ref?
local function parse_autolink(raw, range)
  local target = raw:match "^<([^<>%s]+)>$"
  if not target then
    return nil
  end

  local scheme = uri.scheme(target)
  if not scheme or #scheme < 2 or target:sub(#scheme + 2) == "" then
    return nil
  end

  return {
    kind = "autolink",
    raw = raw,
    range = range,
    target = target,
    label = target,
    embed = false,
  }
end

---@param raw string
---@param range obsidian.Range
---@return obsidian.parse.Ref?
local function parse_footnote(raw, range)
  local id = raw:match "^%[%^([^%]%[%s]+)%]$"
  if not id then
    return nil
  end

  return {
    kind = "footnote",
    raw = raw,
    range = range,
    target = id,
    label = id,
    embed = false,
  }
end

---@class obsidian.parse.refs.Pattern
---@field pattern string
---@field parser fun(raw: string, range: obsidian.Range): obsidian.parse.Ref?

---@type obsidian.parse.refs.Pattern[]
local patterns = {
  -- Single square brackets are valid in note names, so they must not stop
  -- the search for the closing pair of a wiki link.
  { pattern = "%[%[.-%]%]", parser = parse_wiki },
  -- NOTE: Footnote must come before Markdown so that `[^fn](text)` is matched
  -- as a footnote ref instead of a markdown link.
  { pattern = "%[%^[^%]%[%s]+%]", parser = parse_footnote },
  { pattern = "%[[^][]*%]%([^%)]+%)", parser = parse_markdown },
  { pattern = "<[^<>%s]+>", parser = parse_autolink },
}

--- Parse one complete wiki, Markdown, or footnote reference.
---@param raw string
---@param opts? obsidian.parse.line.LineOpts
---@return obsidian.parse.Ref?
function M.parse(raw, opts)
  opts = opts or {}
  local row = opts.row or 0
  local range = Range.new(row, 0, row, #raw)
  for _, entry in ipairs(patterns) do
    local ref = entry.parser(raw, range)
    if ref then
      return ref
    end
  end
end

---@param line string
---@param row integer
---@return obsidian.parse.Ref[]
local function extract_lexical(line, row)
  local matches = {}
  for _, pat in ipairs(patterns) do
    local search_start = 1
    while search_start < #line do
      local start_col, end_col = line:find(pat.pattern, search_start)
      if not start_col or not end_col then
        break
      end

      if not overlaps_ref(matches, start_col, end_col) then
        local ref = parse_match(line, row, start_col, end_col, pat.parser)
        if ref then
          matches[#matches + 1] = ref
        end
      end

      search_start = end_col
    end
  end

  table.sort(matches, function(a, b)
    return a.range.start_col < b.range.start_col
  end)

  return matches
end

---@param document obsidian.parse.Document
---@param row integer Row in the snapshot; may differ from the reported row for isolated text.
---@param matches obsidian.parse.Ref[]
---@return obsidian.parse.Ref[]
local function eligible_refs(document, row, matches)
  if #matches == 0 then
    return matches
  end

  local out = {}
  for _, ref in ipairs(matches) do
    local range = ref.range
    if range.start_row ~= row then
      range = Range.new(row, range.start_col, row, range.end_col)
    end
    -- A ref may contain inline syntax, but it cannot start in an excluded
    -- region or span a comment. Frontmatter can contain refs.
    local origin = Range.new(row, range.start_col, row, range.start_col + 1)
    if
      not document:intersects(origin, Document.INLINE_EXCLUSIONS) and not document:intersects(range, Document.COMMENTS)
    then
      out[#out + 1] = ref
    end
  end
  return out
end

--- Read references on a zero-based row using the existing document snapshot.
--- Returns an empty list for a row outside the snapshot.
---@param document obsidian.parse.Document
---@param row integer
---@return obsidian.parse.Ref[]
function M.on_row(document, row)
  local line = document.lines[row + 1]
  if not line then
    return {}
  end
  return eligible_refs(document, row, extract_lexical(line, row))
end

--- Extract references from isolated text. For a known document use `on_row`.
--- Set `opts.lexical` to return raw tokens without standalone filtering.
---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.Ref[]
function M.extract(line, opts)
  opts = opts or {}
  local matches = extract_lexical(line, opts.row or 0)
  if opts.lexical or #matches == 0 then
    return matches
  end
  return eligible_refs(Document.parse { line }, 0, matches)
end

return M
