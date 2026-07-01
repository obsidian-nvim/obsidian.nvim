--- Shared markdown section parser.
---
--- This is the single source of truth for splitting a note into sections.
--- It backs both anchor-link / block resolution (`Note.from_lines`) and
--- `Note.insert_text` (via `obsidian.util.text_insertion`).

local util = require "obsidian.util"
local Range = require "obsidian.range"

local H1_UNDERLINE_PATTERN = "^(=+)$"
local H2_UNDERLINE_PATTERN = "^(-+)$"
local CODE_BLOCK_PATTERN = "^```[%w_-]*$"

--- A contiguous region of a markdown document.
---
--- All ranges are |obsidian.Range|s over *lines* of the parsed document:
--- cols are always 0 and end rows are exclusive, i.e. a range covering lines
--- 5-7 (1-based) is `{ start_row = 4, start_col = 0, end_row = 7, end_col = 0 }`.
---
---@class obsidian.Section
---
---@field header string|? raw heading label. `nil` for the preamble and for block paragraphs.
---@field level integer|? heading level. `nil` for the preamble and for block paragraphs.
---@field anchor string|? standardized anchor, e.g. "#my-heading".
---@field range obsidian.Range full extent: heading through the content of the last descendant section. This is the range to highlight when navigating here.
---@field heading_range obsidian.Range the heading line(s). Empty for the preamble.
---@field content_range obsidian.Range own content (sub-sections excluded), trimmed of leading and trailing blank lines.
---@field parent obsidian.Section|? the nearest section above with a lower heading level.

local M = {}

---@class obsidian.section.LineDetail
---@field type "text"|"header"|"header-underline"|"code"|"empty"
---@field level integer|?
---@field label string|?

--- Classify lines, resolving setext ("underline") headers retroactively.
---
---@param lines string[]
---@param first integer 1-based index to start at.
---@return table<integer, obsidian.section.LineDetail>
local function get_line_details(lines, first)
  local details = {}
  local in_code_block = false

  ---@param idx integer
  ---@return obsidian.section.LineDetail
  local function classify(idx)
    local line = vim.trim(lines[idx] --[[@as string]])

    if in_code_block then
      in_code_block = not line:match(CODE_BLOCK_PATTERN)
      return { type = "code" }
    elseif line:match(CODE_BLOCK_PATTERN) then
      in_code_block = true
      return { type = "code" }
    end

    if line == "" then
      return { type = "empty" }
    end

    local header = util.parse_header(line)
    if header then
      return { type = "header", level = header.level, label = header.header }
    end

    local prev = details[idx - 1] or { type = "empty" }
    local level = (line:match(H1_UNDERLINE_PATTERN) and 1) or (line:match(H2_UNDERLINE_PATTERN) and 2)
    if level and prev.type == "text" then
      details[idx - 1] = { type = "header", level = level, label = prev.label }
      return { type = "header-underline" }
    end

    return { type = "text", label = line }
  end

  for idx = first, #lines do
    details[idx] = classify(idx)
  end

  return details
end

---@class obsidian.section.ParseOpts
---@field start_row integer|? 0-based row where parsing begins, e.g. just past the frontmatter. Defaults to `0`.
---@field collect_blocks boolean|? also collect block identifiers (`^block-id`).

--- Parse markdown lines into a document-ordered list of sections.
---
--- The first section is always the "preamble" (`header == nil`): everything
--- before the first heading. It is present even when empty.
---
---@param lines string[]
---@param opts obsidian.section.ParseOpts|?
---@return obsidian.Section[] sections
---@return table<string, obsidian.note.Block>|? blocks `nil` unless `opts.collect_blocks` is set.
M.parse = function(lines, opts)
  opts = opts or {}
  local first = (opts.start_row or 0) + 1

  local details = get_line_details(lines, first)

  -- Working entries with 1-based [beg_incl, end_excl) line indices,
  -- mirroring the half-open ranges of the output.
  ---@type { level: integer|?, label: string|?, h_beg: integer, h_end: integer, c_beg: integer, c_end: integer, blocks: obsidian.note.Block[]|? }
  local current = { h_beg = first, h_end = first, c_beg = first, c_end = first }
  local entries = { current }
  local content_empty = true

  ---@type table<string, obsidian.note.Block>|?
  local blocks = opts.collect_blocks and {} or nil
  ---@type integer|?
  local para_beg
  ---@type obsidian.note.Block[]
  local para_blocks = {}
  ---@type obsidian.Section|?
  local last_para_section

  ---@param entry table
  ---@param idx integer
  local function collect_section_block(entry, idx)
    if not blocks then
      return
    end

    local line = vim.trim(lines[idx] or "")
    local block_id = util.parse_block(line)
    if block_id then
      local block = { id = block_id, line = idx, block = line }
      blocks[block_id] = block
      entry.blocks = entry.blocks or {}
      table.insert(entry.blocks, block)
    end
  end

  ---@param end_excl integer
  local function close_paragraph(end_excl)
    if para_beg ~= nil then
      local section = {
        range = Range.new(para_beg - 1, 0, end_excl - 1, 0),
        heading_range = Range.new(para_beg - 1, 0, para_beg - 1, 0),
        content_range = Range.new(para_beg - 1, 0, end_excl - 1, 0),
      }
      for _, block in ipairs(para_blocks) do
        block.section = section
      end
      last_para_section = section
    end
    para_beg = nil
    para_blocks = {}
  end

  for idx = first, #lines do
    local detail = details[idx]
    local idx_excl = idx + 1

    if detail.type == "header" then
      close_paragraph(idx)
      last_para_section = nil
      current = {
        level = detail.level,
        label = detail.label,
        h_beg = idx,
        h_end = idx_excl,
        c_beg = idx_excl,
        c_end = idx_excl,
      }
      table.insert(entries, current)
      collect_section_block(current, idx)
      content_empty = true
    elseif detail.type == "header-underline" then
      current.h_end = idx_excl
      current.c_beg = idx_excl
      current.c_end = idx_excl
    elseif detail.type ~= "empty" then
      if content_empty then
        current.c_beg = idx
        content_empty = false
      end
      current.c_end = idx_excl

      if blocks and detail.type == "text" then
        local line = vim.trim(lines[idx])
        local block_id = util.parse_block(line)
        if block_id and line == block_id and para_beg == nil and last_para_section ~= nil then
          blocks[block_id] = { id = block_id, line = idx, block = line, section = last_para_section }
        else
          para_beg = para_beg or idx
          if block_id then
            local block = { id = block_id, line = idx, block = line }
            blocks[block_id] = block
            table.insert(para_blocks, block)
          end
        end
      else
        close_paragraph(idx)
      end
    else
      close_paragraph(idx)
    end
  end
  close_paragraph(#lines + 1)

  -- Materialize sections. A section's full range extends through its
  -- descendants: it ends where the next section of the same or lower level
  -- begins (or at the end of the document).
  ---@type obsidian.Section[]
  local sections = {}
  for i, entry in ipairs(entries) do
    local full_end = entry.c_end
    if entry.level then
      for j = i + 1, #entries do
        if entries[j].level <= entry.level then
          break
        end
        full_end = math.max(full_end, entries[j].c_end)
      end
    end

    ---@type obsidian.Section
    local section = {
      header = entry.label,
      level = entry.level,
      anchor = entry.label and util.header_to_anchor(entry.label) or nil,
      range = Range.new((entry.level and entry.h_beg or entry.c_beg) - 1, 0, full_end - 1, 0),
      heading_range = Range.new(entry.h_beg - 1, 0, entry.h_end - 1, 0),
      content_range = Range.new(entry.c_beg - 1, 0, entry.c_end - 1, 0),
    }

    if entry.level then
      for j = #sections, 2, -1 do
        if sections[j].level < entry.level then
          section.parent = sections[j]
          break
        end
      end
    end

    for _, block in ipairs(entry.blocks or {}) do
      block.section = section
    end

    sections[i] = section
  end

  return sections, blocks
end

return M
