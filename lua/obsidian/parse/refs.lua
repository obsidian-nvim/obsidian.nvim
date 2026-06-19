local Range = require "obsidian.range"
local search = require "obsidian.search"

local M = {}

---@class obsidian.parse.Ref : obsidian.parse.Match
---@field kind "wiki"|"markdown"
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

---Parse one wiki/markdown ref from raw match text.
---@param raw string Full match, including brackets and optional leading `!`.
---@param kind obsidian.search.RefTypes
---@param range obsidian.Range
---@return obsidian.parse.Ref?
local function parse_ref(raw, kind, range)
  local embed = raw:sub(1, 1) == "!"

  if kind == "Wiki" or kind == "WikiWithAlias" then
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
      embed = embed,
    }
  elseif kind == "Markdown" then
    local label, target = raw:match "^!?%[([^%]]+)%]%(([^%)]+)%)$"
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
      embed = embed,
    }
  end

  return nil
end

---Extract outgoing wiki/markdown links from a single line.
---@param line string
---@param opts obsidian.parse.LineOpts?
---@return obsidian.parse.Ref[]
function M.extract(line, opts)
  opts = opts or {}
  local row = opts.row or 0
  ---@cast row integer

  local out = {}
  local matches = search.find_refs(line, { exclude = { "Tag", "BlockID", "Highlight" } })
  for _, m in ipairs(matches) do
    local m_start, m_end, kind = m[1], m[2], m[3]
    ---@cast m_start integer
    ---@cast m_end integer
    local lead = m_start - 1
    ---@cast lead integer
    if lead >= 1 and line:sub(lead, lead) == "!" then
      m_start = lead
    end

    local raw = line:sub(m_start, m_end)
    local range = Range.new(row, m_start - 1, row, m_end)
    local parsed = parse_ref(raw, kind, range)
    if parsed then
      out[#out + 1] = parsed
    end
  end
  return out
end

return M
