local Range = require "obsidian.range"
local util = require "obsidian.util"

local M = {}

---@alias obsidian.parse.RefKind "wiki"|"markdown"|"footnote"

---@class obsidian.parse.Ref : obsidian.parse.Match
---@field kind obsidian.parse.RefKind
---@field target string
---@field label string?
---@field anchor string?
---@field block string?
---@field embed boolean

---@param target string
---@return string target
---@return string? anchor
---@return string? block
local function split_fragment(target)
  local anchor, block
  local hash = target:find("#", 1, true)
  if hash then
    local frag = target:sub(hash + 1)
    target = target:sub(1, hash - 1)
    if frag:sub(1, 1) == "^" then
      block = frag:sub(2)
    else
      anchor = frag
    end
  end
  return target, anchor, block
end

---@param line string
---@return [integer, integer][]
local function inline_code_ranges(line)
  local ranges = {}
  for start_col, end_col in util.gfind(line, "`[^`]*`") do
    ranges[#ranges + 1] = { start_col, end_col }
  end
  return ranges
end

---@param ranges [integer, integer][]
---@param start_col integer
---@param end_col integer
---@return boolean
local function inside_inline_code(ranges, start_col, end_col)
  for _, range in ipairs(ranges) do
    if range[1] < start_col and end_col < range[2] then
      return true
    end
  end
  return false
end

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
    target = body:sub(1, pipe - 1)
    label = body:sub(pipe + 1)
  end

  local anchor, block
  target, anchor, block = split_fragment(target)
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
  target, anchor, block = split_fragment(target)
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
  { pattern = "%[%[[^][]+%]%]", parser = parse_wiki },
  -- NOTE: Footnote must come before Markdown so that `[^fn](text)` is matched
  -- as a footnote ref instead of a markdown link.
  { pattern = "%[%^[^%]%[%s]+%]", parser = parse_footnote },
  { pattern = "%[[^][]*%]%([^%)]+%)", parser = parse_markdown },
}

---Extract outgoing wiki/markdown/footnote refs from a single line.
---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.Ref[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local out = {}
  local code_ranges = inline_code_ranges(line)

  for _, pat in ipairs(patterns) do
    local search_start = 1
    while search_start < #line do
      local start_col, end_col = line:find(pat.pattern, search_start)
      if not start_col or not end_col then
        break
      end

      if not inside_inline_code(code_ranges, start_col, end_col) and not overlaps_ref(out, start_col, end_col) then
        local ref = parse_match(line, row, start_col, end_col, pat.parser)
        if ref then
          out[#out + 1] = ref
        end
      end

      search_start = end_col
    end
  end

  table.sort(out, function(a, b)
    return a.range.start_col < b.range.start_col
  end)

  return out
end

return M
