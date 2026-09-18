local Range = require "obsidian.range"
local link_parser = require "obsidian.link.parser"

local M = {}

---@alias obsidian.parse.RefKind "wiki"|"markdown"|"footnote"

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

--- Extract wiki/markdown/footnote refs from a line. By default this applies
--- standalone document filtering; set `opts.lexical` when a full-document
--- consumer will apply filtering against its shared snapshot.
---@param line string
---@param opts obsidian.parse.line.LineOpts?
---@return obsidian.parse.Ref[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

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

  if opts.lexical then
    return matches
  end

  local Document = require "obsidian.parse.document"
  local document = Document.parse { line }
  local out = {}
  for _, ref in ipairs(matches) do
    local local_range = Range.new(0, ref.range.start_col, 0, ref.range.end_col)
    local origin = Range.new(0, ref.range.start_col, 0, ref.range.start_col + 1)
    if
      not document:intersects(origin, Document.BODY_EXCLUSIONS)
      and not document:intersects(local_range, Document.COMMENTS)
    then
      out[#out + 1] = ref
    end
  end
  return out
end

return M
