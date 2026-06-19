local search = require "obsidian.search"

local M = {}

---@class obsidian.parse.Ref
---@field kind "wiki"|"markdown"
---@field raw string
---@field target string
---@field label string?
---@field anchor string?
---@field block string?
---@field embed boolean
---@field line integer?
---@field col integer?

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
---@return obsidian.parse.Ref?
function M.parse_ref(raw, kind)
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
---@param lnum integer? 1-based line number to attach to matches.
---@return obsidian.parse.Ref[]
function M.extract_links(line, lnum)
  local out = {}
  local matches = search.find_refs(line, { exclude = { "Tag", "BlockID", "Highlight" } })
  for _, m in ipairs(matches) do
    local m_start, m_end, kind = m[1], m[2], m[3]
    local lead = m_start - 1
    if lead >= 1 and line:sub(lead, lead) == "!" then
      m_start = lead
    end

    local raw = line:sub(m_start, m_end)
    local parsed = M.parse_ref(raw, kind)
    if parsed then
      if lnum ~= nil then
        parsed.line = lnum
      end
      parsed.col = m_start
      out[#out + 1] = parsed
    end
  end
  return out
end

return M
