local Note = require "obsidian.note"
local parse_refs = require "obsidian.parse.refs"
local parse_tags = require "obsidian.parse.tags"
local search_files = require "obsidian.search.files"
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

---Extract outgoing links from a single line.
---@param line string
---@param lnum integer  1-based
---@return table[]
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

---@param range obsidian.Range
---@return table
local function range_row(range)
  return {
    start_line = range.start_row + 1,
    end_line = range.end_row,
  }
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

  local extension = search_files.extension(abs_path)
  local filename = vim.fs.basename(abs_path)
  local relative_path = abs_path
  local root = vim.fs.normalize(_vault_root):gsub("/+$", "")
  if vim.startswith(vim.fs.normalize(abs_path), root .. "/") then
    relative_path = vim.fs.normalize(abs_path):sub(#root + 2)
  end

  if extension == "canvas" then
    return {
      kind = "canvas",
      relative_path = relative_path,
      extension = extension,
      filename = filename,
      basename = vim.fn.fnamemodify(filename, ":r"),
      line_count = #lines,
      mtime = stat.mtime.sec,
      mtime_nsec = stat.mtime.nsec,
      size = stat.size,
    }
  end

  local ok, note = pcall(Note.from_lines, lines, abs_path, {
    collect_anchor_links = true,
    collect_blocks = true,
    collect_sections = true,
    max_lines = #lines,
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
  local tag_locations = {}
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

  local frontmatter = frontmatter_snapshot(lines)
  local frontmatter_tags = frontmatter.values.tags
  if frontmatter_tags ~= nil then
    local values = {}
    flatten(frontmatter_tags, values)
    for _, tag in ipairs(values) do
      ---@cast tag string
      local text = vim.startswith(tag, "#") and tag or "#" .. tag
      tag_locations[#tag_locations + 1] = {
        text = text,
        normalized = text:lower(),
        line = 1,
        source = "frontmatter",
      }
    end
  end

  local fm_end = note.frontmatter_end_line or 0
  local links_out = {}
  local tasks = {}
  local fence
  for i = fm_end + 1, #lines do
    local line = lines[i] or ""
    local marker = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
    if marker then
      if not line:match "^%s*[`~][`~][`~].*[`~][`~][`~]%s*$" then
        if not fence then
          fence = marker:sub(1, 1)
        elseif marker:sub(1, 1) == fence then
          fence = nil
        end
      end
    elseif not fence then
      for _, l in ipairs(extract_links(line, i)) do
        links_out[#links_out + 1] = l
      end
      for _, tag_match in ipairs(parse_tags.extract(line, { row = i - 1 })) do
        add_tag(tag_match.tag)
        tag_locations[#tag_locations + 1] = {
          text = "#" .. tag_match.tag,
          normalized = ("#" .. tag_match.tag):lower(),
          line = i,
          col = tag_match.range.start_col + 1,
          source = "inline",
        }
      end
      local indent, state, text = match_task(line)
      if indent ~= nil then
        tasks[#tasks + 1] = {
          line = i,
          indent = indent,
          state = state,
          text = text,
          raw = line,
          col = assert(line:find(text, 1, true)),
        }
      end
    end
  end

  local row = {
    kind = "markdown",
    relative_path = relative_path,
    extension = extension,
    filename = filename,
    basename = vim.fn.fnamemodify(filename, ":r"),
    line_count = #lines,
    id = tostring(note.id),
    title = note.title or frontmatter.values.title,
    mtime = stat.mtime.sec,
    mtime_nsec = stat.mtime.nsec,
    size = stat.size,
  }
  row.frontmatter = frontmatter
  if note.aliases and #note.aliases > 0 then
    row.aliases = note.aliases
  end
  if #tags_lower > 0 then
    row.tags = tags_lower
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

  local headings = {}
  local sections = {}
  for _, section in ipairs(note.sections or {}) do
    local section_row = range_row(section.range)
    sections[#sections + 1] = section_row
    if section.header then
      local heading = vim.tbl_extend("force", section_row, {
        text = section.header,
        level = section.level,
        anchor = section.anchor,
      })
      headings[#headings + 1] = heading
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
    local block_row = block.section and range_row(block.section.range)
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
