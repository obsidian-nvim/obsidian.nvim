local Document = require "obsidian.parse.document"
local Note = require "obsidian.note"
local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"
local parse_tasks = require "obsidian.parse.line.tasks"
local tags = require "obsidian.tag"
local yaml = require "obsidian.yaml"

local M = {}

---@param value any
---@param out string[]
local function flatten(value, out)
  if value == vim.NIL or value == nil then
    return
  elseif type(value) == "table" then
    for key, item in pairs(value) do
      if not vim.islist(value) then
        out[#out + 1] = tostring(key)
      end
      flatten(item, out)
    end
  else
    out[#out + 1] = tostring(value)
  end
end

---@param lines string[]
---@return table
local function frontmatter_snapshot(lines)
  if not lines[1] or not lines[1]:match "^%-%-%-+%s*$" then
    return { present = false, values = {} }
  end

  local source = {}
  for i = 2, #lines do
    if lines[i]:match "^%-%-%-+%s*$" then
      local ok, values = pcall(yaml.loads, table.concat(source, "\n"))
      return {
        present = true,
        start_line = 1,
        end_line = i,
        values = ok and type(values) == "table" and values or {},
      }
    end
    source[#source + 1] = lines[i]
  end

  return { present = true, start_line = 1, values = {} }
end

---Extract outgoing links from a single line, excluding non-body syntax.
---@param line string
---@param lnum integer 1-based
---@param document obsidian.parse.Document
---@return table[]
local function extract_links(line, lnum, document)
  local out = {}
  for _, ref in ipairs(parse_refs.extract(line, { row = lnum - 1, lexical = true })) do
    local origin = Range.new(lnum - 1, ref.range.start_col, lnum - 1, ref.range.start_col + 1)
    if
      (ref.kind == "wiki" or ref.kind == "markdown")
      and not document:intersects(origin, Document.INLINE_EXCLUSIONS)
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

---@param range obsidian.Range
---@return table
local function range_row(range)
  return { start_line = range.start_row + 1, end_line = range.end_row }
end

---Convert a note and its stat data into a compact typed cache row.
---@param abs_path string
---@param vault_root string
---@return table? row
function M.build(abs_path, vault_root)
  local stat = vim.uv.fs_stat(abs_path)
  if not stat or stat.type ~= "file" then
    return nil
  end

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
    collect_anchor_links = true,
    collect_blocks = true,
    collect_sections = true,
    max_lines = #lines,
    document = document,
  })
  if not ok or not note then
    return nil
  end

  local root = vim.fs.normalize(vault_root):gsub("/+$", "")
  local normalized_path = vim.fs.normalize(abs_path)
  local relative_path = normalized_path
  if vim.startswith(normalized_path, root .. "/") then
    relative_path = normalized_path:sub(#root + 2)
  end
  local filename = vim.fs.basename(abs_path)
  local frontmatter = frontmatter_snapshot(lines)
  local properties = vim.deepcopy(note.metadata or {})
  if #note.aliases == 0 then
    properties.aliases = nil
  end
  if #note.tags == 0 then
    properties.tags = nil
  end

  local tag_values, tag_seen, tag_locations = {}, {}, {}
  for _, occurrence in
    ipairs(tags.extract(lines, {
      frontmatter_end_line = note.frontmatter_end_line,
      frontmatter_elements = note.frontmatter_elements,
      document = document,
    }))
  do
    local normalized = tags.normalize(occurrence.tag)
    if normalized ~= "" and not tag_seen[normalized] then
      tag_seen[normalized] = true
      tag_values[#tag_values + 1] = normalized
    end
    tag_locations[#tag_locations + 1] = {
      text = occurrence.source == "inline" and occurrence.raw or ("#" .. occurrence.tag),
      normalized = "#" .. normalized,
      line = occurrence.source == "frontmatter" and 1 or occurrence.range.start_row + 1,
      col = occurrence.source == "inline" and occurrence.range.start_col + 1 or nil,
      source = occurrence.source,
    }
  end

  local links_out, tasks = {}, {}
  for i, line in ipairs(lines) do
    for _, link in ipairs(extract_links(line, i, document)) do
      links_out[#links_out + 1] = link
    end
    local task = parse_tasks.extract(line, { row = i - 1 })[1]
    if
      task
      and task.task_marker_col
      and not document:intersects(
        Range.new(i - 1, task.task_marker_col, i - 1, task.task_marker_col + 3),
        Document.BODY_EXCLUSIONS
      )
    then
      tasks[#tasks + 1] = {
        line = i,
        indent = task.indent,
        state = task.task_state,
        text = task.text,
        raw = line,
        col = task.text_col + 1,
      }
    end
  end

  local row = {
    kind = "note",
    search_kind = "markdown",
    stat = {
      mtime_sec = stat.mtime.sec,
      mtime_nsec = stat.mtime.nsec,
      size = stat.size,
    },
    relative_path = relative_path,
    extension = (filename:match "%.([^./]+)$" or ""):lower(),
    filename = filename,
    basename = vim.fn.fnamemodify(filename, ":r"),
    line_count = #lines,
    id = tostring(note.id),
    title = note.title or frontmatter.values.title,
    frontmatter = frontmatter,
  }
  if note.aliases and #note.aliases > 0 then
    row.aliases = vim.deepcopy(note.aliases)
  end
  if #tag_values > 0 then
    row.tags = tag_values
  end
  if #tag_locations > 0 then
    row.tag_locations = tag_locations
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

  local headings, sections = {}, {}
  for _, section in ipairs(note.sections or {}) do
    if section.range then
      sections[#sections + 1] = range_row(section.range)
    end
    if section.header then
      headings[#headings + 1] = {
        header = section.header,
        anchor = section.anchor,
        level = section.level,
        line = section.heading_range.start_row + 1,
      }
    end
  end
  if #sections > 0 then
    row.sections = sections
  end
  if #headings > 0 then
    row.headings = headings
  end

  local blocks = {}
  for id, block in pairs(note.blocks or {}) do
    local block_row = block.section and block.section.range and range_row(block.section.range)
      or { start_line = block.line, end_line = block.line }
    block_row.id = id
    blocks[#blocks + 1] = block_row
  end
  table.sort(blocks, function(a, b)
    if a.start_line == b.start_line then
      return a.id < b.id
    end
    return a.start_line < b.start_line
  end)
  if #blocks > 0 then
    row.blocks = blocks
  end

  return row
end

return M
