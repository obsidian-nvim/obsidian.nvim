local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local parse_tags = require "obsidian.parse.tags"
local yaml = require "obsidian.yaml"

local M = {}

---@class obsidian.TagOccurrence
---@field tag string Tag text without a leading `#`.
---@field raw string Matched source text; inline tags include `#`, while YAML quotes are excluded.
---@field source "inline"|"frontmatter"
---@field text string Original source line.
---@field range obsidian.Range Range of the tag name (or `#tag` for inline tags).

---Return the canonical identity of a tag.
---@param text string
---@return string
M.normalize = function(text)
  if vim.startswith(text, "#") then
    text = text:sub(2)
  end
  return vim.fn.tolower(text)
end

---Match a tag against a query.
---@param tag string
---@param query string
---@param mode? "exact"|"subtree"|"prefix"
---@return boolean
M.matches = function(tag, query, mode)
  tag = M.normalize(tag)
  query = M.normalize(query)
  mode = mode or "prefix"

  if query == "" then
    return true
  elseif mode == "exact" then
    return tag == query
  elseif mode == "subtree" then
    return tag == query or vim.startswith(tag, query .. "/")
  elseif mode == "prefix" then
    return vim.startswith(tag, query)
  else
    error("invalid tag matching mode: " .. tostring(mode))
  end
end

---Adapt a single-line YAML scalar's lexical extent to the tag-name extent.
---Keep source bytes (including escapes) separate from the decoded tag value.
---@param lines string[]
---@param element obsidian.yaml.Element
---@return obsidian.TagOccurrence?
local function frontmatter_tag(lines, element)
  local path, range = element.path, element.range
  if path[1] ~= "tags" or not (#path == 1 or (#path == 2 and type(path[2]) == "number")) then
    return nil
  end
  if range.start_row ~= range.end_row or (type(element.value) ~= "string" and type(element.value) ~= "number") then
    return nil
  end

  local tag = tostring(element.value)
  local line = lines[range.start_row + 1] or ""
  local start_col, end_col = range.start_col, range.end_col
  local source = line:sub(start_col + 1, end_col)
  local quote = source:sub(1, 1)
  if (quote == [["]] or quote == [[']]) and source:sub(-1) == quote then
    start_col = start_col + 1
    end_col = end_col - 1
  end
  if vim.startswith(tag, "#") then
    tag = tag:sub(2)
    start_col = start_col + 1
  end
  if tag == "" or start_col >= end_col then
    return nil
  end
  ---@cast start_col integer
  ---@cast end_col integer
  return {
    tag = tag,
    raw = line:sub(start_col + 1, end_col),
    source = "frontmatter",
    text = line,
    range = Range.new(range.start_row, start_col, range.end_row, end_col),
  }
end

---@param lines string[]
---@param last_line integer 1-based closing frontmatter boundary.
---@param out obsidian.TagOccurrence[]
---@param elements obsidian.yaml.Element[]? Already parsed from the same snapshot, in document coordinates.
local function extract_frontmatter_tags(lines, last_line, out, elements)
  if elements == nil then
    local body = vim.list_slice(lines, 2, last_line - 1)
    local ok, _, _, parsed = pcall(yaml.loads, body, { base_row = 1 })
    if not ok then
      return
    end
    elements = parsed
  end
  for _, element in ipairs(elements) do
    local occurrence = frontmatter_tag(lines, element)
    if occurrence then
      out[#out + 1] = occurrence
    end
  end
end

---Extract source-aware tag occurrences from Markdown lines.
---@param lines string[]
---@param opts? { frontmatter_end_line: integer?, frontmatter_elements: obsidian.yaml.Element[]?, document: obsidian.parse.Document? }
---@return obsidian.TagOccurrence[]
M.extract = function(lines, opts)
  opts = opts or {}
  local out = {}
  local document = opts.document or Document.parse(lines)
  local frontmatter = document.frontmatter
  local frontmatter_end = opts.frontmatter_end_line
    or (frontmatter and frontmatter.termination == "delimiter" and frontmatter.range.end_row or nil)

  if frontmatter_end then
    extract_frontmatter_tags(lines, frontmatter_end, out, opts.frontmatter_elements)
  end

  local first_body_line
  if frontmatter_end then
    first_body_line = frontmatter_end + 1
  elseif frontmatter then
    first_body_line = #lines + 1
  else
    first_body_line = 1
  end

  for i = first_body_line, #lines do
    local line = lines[i] or ""
    for _, match in ipairs(parse_tags.extract(line, { row = i - 1, lexical = true })) do
      if not document:intersects(match.range, Document.BODY_EXCLUSIONS) then
        out[#out + 1] = {
          tag = match.tag,
          raw = match.raw,
          source = "inline",
          text = line,
          range = match.range,
        }
      end
    end
  end

  table.sort(out, function(a, b)
    if a.range.start_row ~= b.range.start_row then
      return a.range.start_row < b.range.start_row
    end
    return a.range.start_col < b.range.start_col
  end)
  return out
end

return M
