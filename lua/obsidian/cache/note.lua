local Document = require "obsidian.parse.document"
local Note = require "obsidian.note"
local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"
local parse_tags = require "obsidian.parse.tags"
local tags = require "obsidian.tag"

local M = {}

---Extract outgoing links from a single line.
---@param line string
---@param lnum integer  1-based
---@param document obsidian.parse.Document
---@return table[]
local function extract_links(line, lnum, document)
  local out = {}
  for _, ref in ipairs(parse_refs.extract(line, { row = lnum - 1, lexical = true })) do
    local origin = Range.new(lnum - 1, ref.range.start_col, lnum - 1, ref.range.start_col + 1)
    if
      (ref.kind == "wiki" or ref.kind == "markdown")
      and not document:intersects(origin, Document.BODY_EXCLUSIONS)
      and not document:intersects(ref.range, Document.COMMENTS)
    then
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
---@return integer? indent, string? state, string? text, integer? marker_col
local function match_task(line)
  -- bullet list
  local indent, state, text = line:match "^(%s*)[-%*%+] %[(.)%] (.*)$"
  if state then
    return #indent, state, text, assert(line:find("[", 1, true)) - 1
  end
  -- numbered list
  indent, state, text = line:match "^(%s*)%d+%. %[(.)%] (.*)$"
  if state then
    return #indent, state, text, assert(line:find("[", 1, true)) - 1
  end
  return nil, nil, nil, nil
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

  local document = Document.parse(lines)
  local ok, note = pcall(Note.from_lines, lines, abs_path, {
    collect_sections = true,
    max_lines = #lines,
    document = document,
  })
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
  local tags_seen = {}
  local function add_tag(tag)
    tag = tags.normalize(tag)
    if tag ~= "" and not tags_seen[tag] then
      tags_lower[#tags_lower + 1] = tag
      tags_seen[tag] = true
    end
  end
  for _, occurrence in
    ipairs(tags.extract(lines, {
      frontmatter_end_line = note.frontmatter_end_line,
      frontmatter_elements = note.frontmatter_elements,
    }))
  do
    add_tag(occurrence.tag)
  end

  local headings = {}
  for _, section in ipairs(note.sections or {}) do
    if section.header then
      headings[#headings + 1] = {
        header = section.header,
        anchor = section.anchor,
        level = section.level,
        line = section.heading_range.start_row + 1,
      }
    end
  end

  local body_start = document.frontmatter and document.frontmatter.range.end_row or 0
  local links_out = {}
  local tasks = {}
  for i = body_start + 1, #lines do
    local line = lines[i] or ""
    for _, link in ipairs(extract_links(line, i, document)) do
      links_out[#links_out + 1] = link
    end
    for _, tag_match in ipairs(parse_tags.extract(line, { row = i - 1, lexical = true })) do
      if not document:intersects(tag_match.range, Document.BODY_EXCLUSIONS) then
        add_tag(tag_match.tag)
      end
    end
    local indent, state, text, marker_col = match_task(line)
    if
      indent ~= nil
      and marker_col ~= nil
      and not document:intersects(Range.new(i - 1, marker_col, i - 1, marker_col + 3), Document.BODY_EXCLUSIONS)
    then
      tasks[#tasks + 1] = {
        line = i,
        indent = indent,
        state = state,
        text = text,
      }
    end
  end

  local row = {
    kind = "note",
    stat = {
      mtime_sec = stat.mtime.sec,
      mtime_nsec = stat.mtime.nsec,
      size = stat.size,
    },
  }
  local basename = vim.fn.fnamemodify(abs_path, ":t:r")
  if tostring(note.id) ~= basename then
    row.id = note.id
  end
  if note.aliases and #note.aliases > 0 then
    row.aliases = note.aliases
  end
  if #tags_lower > 0 then
    row.tags = tags_lower
  end
  if next(properties) ~= nil then
    row.properties = properties
  end
  if #headings > 0 then
    row.headings = headings
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
