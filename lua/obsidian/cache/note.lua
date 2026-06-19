local Note = require "obsidian.note"
local search = require "obsidian.search"

local M = {}

---Parse one wiki/markdown ref from raw match text.
---@param raw string  full match incl. brackets
---@param kind obsidian.search.RefTypes
---@return { kind: "wiki"|"markdown", raw: string, target: string, label: string?, anchor: string?, block: string?, embed: boolean }?
local function parse_ref(raw, kind)
  local embed = false
  if raw:sub(1, 1) == "!" then
    embed = true
  end

  if kind == "Wiki" or kind == "WikiWithAlias" then
    local body = raw:match "^!?%[%[(.+)%]%]$"
    if not body then
      return nil
    end
    local target_part, label = body, nil
    local pipe = body:find("|", 1, true)
    if pipe then
      target_part = body:sub(1, pipe - 1)
      label = body:sub(pipe + 1)
    end
    local anchor, block
    local hash = target_part:find("#", 1, true)
    if hash then
      local frag = target_part:sub(hash + 1)
      target_part = target_part:sub(1, hash - 1)
      if frag:sub(1, 1) == "^" then
        block = frag:sub(2)
      else
        anchor = frag
      end
    end
    return {
      kind = "wiki",
      raw = raw,
      target = target_part,
      label = label,
      anchor = anchor,
      block = block,
      embed = embed,
    }
  elseif kind == "Markdown" then
    local label, target_part = raw:match "^!?%[([^%]]+)%]%(([^%)]+)%)$"
    if not target_part then
      return nil
    end
    local anchor, block
    local hash = target_part:find("#", 1, true)
    if hash then
      local frag = target_part:sub(hash + 1)
      target_part = target_part:sub(1, hash - 1)
      if frag:sub(1, 1) == "^" then
        block = frag:sub(2)
      else
        anchor = frag
      end
    end
    return {
      kind = "markdown",
      raw = raw,
      target = target_part,
      label = label,
      anchor = anchor,
      block = block,
      embed = embed,
    }
  end
  return nil
end

---Extract outgoing links from a single line.
---@param line string
---@param lnum integer  1-based
---@return table[]
local function extract_links(line, lnum)
  local out = {}
  local matches = search.find_refs(line, { exclude = { "Tag", "BlockID", "Highlight" } })
  for _, m in ipairs(matches) do
    local m_start, m_end, kind = m[1], m[2], m[3]
    -- include leading `!` if present (embed)
    local lead = m_start - 1
    if lead >= 1 and line:sub(lead, lead) == "!" then
      m_start = lead
    end
    local raw = line:sub(m_start, m_end)
    local parsed = parse_ref(raw, kind)
    if parsed then
      parsed.line = lnum
      parsed.col = m_start
      out[#out + 1] = parsed
    end
  end
  return out
end

---Match `- [x] foo` / `* [ ] foo` / `1. [ ] foo`. Captures indent, state, text.
---@param line string
---@return integer? indent, string? state, string? text
local function match_task(line)
  -- bullet list
  local indent, state, text = line:match "^(%s*)[-%*%+] %[(.)%] (.*)$"
  if state then
    return #indent, state, text
  end
  -- numbered list
  indent, state, text = line:match "^(%s*)%d+%. %[(.)%] (.*)$"
  if state then
    return #indent, state, text
  end
  return nil, nil, nil
end

---Convert obsidian.Note + stat → CacheNote row.
---@param abs_path string
---@param _vault_root string
---@return table? row
function M.build(abs_path, _vault_root)
  local stat = vim.uv.fs_stat(abs_path)
  if not stat or stat.type ~= "file" then
    return nil
  end

  -- Read file once; reuse lines for both Note parser and link/task extractors.
  local fh = io.open(abs_path, "r")
  if not fh then
    return nil
  end
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = line
  end
  fh:close()

  local ok, note = pcall(Note.from_lines, lines, abs_path, {})
  if not ok or not note then
    return nil
  end

  local properties = {}
  if note.metadata then
    for k, v in pairs(note.metadata) do
      properties[k] = v
    end
  end
  local tags_lower = {}
  for _, t in ipairs(note.tags or {}) do
    tags_lower[#tags_lower + 1] = t:lower()
  end

  local fm_end = note.frontmatter_end_line or 0
  local links_out = {}
  local tasks = {}
  local in_code_block = false
  for i = fm_end + 1, #lines do
    local line = lines[i]
    if line:match "^%s*```" then
      in_code_block = not in_code_block
    elseif not in_code_block then
      for _, l in ipairs(extract_links(line, i)) do
        links_out[#links_out + 1] = l
      end
      local indent, state, text = match_task(line)
      if indent ~= nil then
        tasks[#tasks + 1] = {
          line = i,
          indent = indent,
          state = state,
          text = text,
        }
      end
    end
  end

  local row = {
    mtime = stat.mtime.sec,
    size = stat.size,
  }
  if note.aliases and #note.aliases > 0 then
    row.aliases = note.aliases
  end
  if #tags_lower > 0 then
    row.tags = tags_lower
  end
  if next(properties) ~= nil then
    row.properties = properties
  end
  if #links_out > 0 then
    row.links_out = links_out
  end
  if #tasks > 0 then
    row.tasks = tasks
  end
  return row
end

return M
