local Note = require "obsidian.note"
local parse_refs = require "obsidian.parse.refs"
local parse_tags = require("obsidian.parse.tags").parse_tags

local M = {}

---Extract outgoing links from a single line.
---@param line string
---@param lnum integer  1-based
---@return obsidian.cache.LinkRow[]
local function extract_links(line, lnum)
  local out = {}
  for _, ref in ipairs(parse_refs.extract(line, { row = lnum - 1 })) do
    if ref.kind == "wiki" or ref.kind == "markdown" then
      out[#out + 1] = {
        kind = ref.kind,
        raw = ref.raw,
        target = ref.target,
        label = ref.label,
        anchor = ref.anchor,
        block = ref.block,
        embed = ref.embed,
        line = lnum,
        col = ref.range.start_col + 1,
      }
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
---@return obsidian.cache.NoteRow? row
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

  ---@type table<string, any>
  local properties = {}
  if note.metadata then
    for k, v in pairs(note.metadata) do
      properties[k] = v
    end
  end
  ---@type string[]
  local tags_lower = {}
  local tags_seen = {}
  local function add_tag(tag)
    tag = tag:lower()
    if tag ~= "" and not tags_seen[tag] then
      tags_lower[#tags_lower + 1] = tag
      tags_seen[tag] = true
    end
  end
  for _, t in ipairs(note.tags or {}) do
    add_tag(t)
  end

  local fm_end = note.frontmatter_end_line or 0
  ---@type obsidian.cache.LinkRow[]
  local links_out = {}
  ---@type obsidian.cache.TaskRow[]
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
      for _, tag in ipairs(parse_tags(line)) do
        add_tag(line:sub(tag[1] + 1, tag[2]))
      end
      local indent, state, text = match_task(line)
      if indent ~= nil and state ~= nil and text ~= nil then
        tasks[#tasks + 1] = {
          line = i,
          indent = indent,
          state = state,
          text = text,
        }
      end
    end
  end

  ---@type obsidian.cache.NoteRow
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
