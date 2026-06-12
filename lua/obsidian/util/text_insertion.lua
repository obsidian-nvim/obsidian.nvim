local Section = require "obsidian.section"
local Range = require "obsidian.range"

local M = {}
local H = {}

--- Resolves the changes needed to insert text into the given markdown document while preserving the given constraints.
---
---@param lines string[] The list of lines in the markdown document.
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer insert_idx where new text should be inserted to satisfy the constraints, or `0` when impossible.
---@return string[] insert_top holds the lines needed _before_ the text in order to preserve the constraints.
---@return string[] insert_bot holds the lines needed _after_ the text in order to preserve the constraints.
function M.resolve(lines, opts)
  local sections = H.parse_sections(lines)
  local chosen_idx = H.choose_section(sections, opts)

  if chosen_idx > 0 then
    return H.expand_old_section(sections, chosen_idx, opts)
  else
    local key = opts.on_section_missing or "create"
    local handler = assert(H.on_section_missing_handlers[key], "unknown `on_section_missing` key: " .. vim.inspect(key))
    return handler(sections, opts)
  end
end

--- Parse markdown sections and append an empty EOF marker.
---
--- IMPORTANT: There will always be AT LEAST TWO sections:
--- - the first is the preamble from `obsidian.section`;
--- - the final one is an empty EOF marker used as an insertion target.
---
---@param lines string[] The list of lines in the markdown document.
---@return obsidian.Section[] sections
function H.parse_sections(lines)
  local sections = Section.parse(lines)
  local eof_row = sections[#sections].content_range.end_row
  local eof_range = Range.new(eof_row, 0, eof_row, 0)

  sections[#sections + 1] = {
    range = eof_range,
    heading_range = eof_range,
    content_range = eof_range,
  }

  return sections
end

---@param range obsidian.Range
---@return integer
local function beg_incl(range)
  return range.start_row + 1
end

---@param range obsidian.Range
---@return integer
local function end_excl(range)
  return range.end_row + 1
end

--- Chooses a section to insert new text into.
---
---@param sections obsidian.Section[] List of sections in the document. Must contain the preamble and EOF-marker.
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer chosen_idx where the new text can be inserted while maintaining the layout, or `0` if none are valid.
function H.choose_section(sections, opts)
  local header_wanted = opts.section.header
  local level_wanted = opts.section.level

  if not header_wanted and not level_wanted then
    return 1
  end

  for idx = 2, #sections - 1 do
    local section = sections[idx]
    if
      (not header_wanted or section.header == header_wanted) and (not level_wanted or section.level == level_wanted)
    then
      return idx
    end
  end

  return 0
end

--- Expands the section positioned at the specified index so that it can have more text inserted into it.
---
---@param sections obsidian.Section[] List of sections in the document. Must contain the preamble and EOF-marker.
---@param chosen_idx integer The index where the old section is located. Must NOT be the EOF-marker (`idx = #sections`).
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer insert_idx where new text should be inserted to satisfy the constraints.
---@return string[] insert_top holds the lines needed _before_ the text in order to preserve the constraints.
---@return string[] insert_bot holds the lines needed _after_ the text in order to preserve the constraints.
function H.expand_old_section(sections, chosen_idx, opts)
  assert(chosen_idx < #sections, "EOF-marker cannot have content placed into it.")

  local section_chosen = sections[chosen_idx]
  local section_after = sections[chosen_idx + 1]

  local insert_idx = opts.placement == "top" and beg_incl(section_chosen.content_range)
    or end_excl(section_chosen.content_range)
  local insert_top = {}
  local insert_bot = {}

  if H.is_content_empty(section_chosen) then
    table.insert(insert_top, "")
  end

  if not H.is_section_empty(section_after) and beg_incl(section_after.heading_range) == insert_idx then
    table.insert(insert_bot, "")
  end

  return insert_idx, insert_top, insert_bot
end

--- Inserts a new heading and section at the specified index and "pushes down" the section that is currently there.
---
---@param sections obsidian.Section[] List of sections in the document. Must contain the preamble and EOF-marker.
---@param chosen_idx integer The index where the new section will be inserted. Must NOT be the preamble (`idx = 1`).
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer insert_idx where new text should be inserted to satisfy the constraints.
---@return string[] insert_top holds the lines needed _before_ the text in order to preserve the constraints.
---@return string[] insert_bot holds the lines needed _after_ the text in order to preserve the constraints.
function H.insert_new_section(sections, chosen_idx, opts)
  assert(chosen_idx > 1, "Preamble cannot have header placed before it.")

  local section_chosen = sections[chosen_idx]
  local section_before = sections[chosen_idx - 1]

  local insert_idx = beg_incl(section_chosen.heading_range)
  local insert_top = {}
  local insert_bot = {}

  if
    (not H.is_section_empty(section_before) or opts.padding_top)
    and end_excl(section_before.content_range) == insert_idx
  then
    table.insert(insert_top, "")
  end

  table.insert(insert_top, string.rep("#", opts.section.level or 2) .. " " .. (opts.section.header or "Untitled"))
  table.insert(insert_top, "")

  if not H.is_section_empty(section_chosen) then
    table.insert(insert_bot, "")
  end

  return insert_idx, insert_top, insert_bot
end

---@type table<string, obsidian.note.OnSectionMissingHandler>
H.on_section_missing_handlers = {
  cancel = function(_, _)
    return 0, {}, {}
  end,

  error = function(_, opts)
    error("Failed to find section: " .. vim.inspect { header = opts.section.header, level = opts.section.level })
  end,

  create = function(sections, opts)
    -- TODO: The choice made here is arbitrary but users may want more precise control (e.g., "insert after section X").
    local chosen_idx = opts.placement == "bot" and #sections or 2

    return H.insert_new_section(sections, chosen_idx, opts)
  end,
}

---@param section? obsidian.Section
---@return boolean
function H.is_section_empty(section)
  return not section or beg_incl(section.heading_range) == end_excl(section.content_range)
end

---@param section? obsidian.Section
---@return boolean
function H.is_content_empty(section)
  return not section or Range.is_empty(section.content_range)
end

---@alias obsidian.note.OnSectionMissingHandler fun(sections: obsidian.Section[], opts: obsidian.note.InsertTextOpts): insert_idx: integer, insert_top: string[], insert_bot: string[]

return M
