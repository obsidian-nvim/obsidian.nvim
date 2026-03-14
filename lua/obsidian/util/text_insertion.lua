local HEADER_PREFIX_PATTERN = "^(#+)%s*(%S.*)$"
local H1_UNDERLINE_PATTERN = "^(=+)$"
local H2_UNDERLINE_PATTERN = "^(-+)$"
local CODE_BLOCK_PATTERN = "^```[%w_-]*$"

local M = {}
local H = {}

--- Resolves the information needed to insert text into the given markdown document while preserving the desired layout.
---
---@param lines string[] The list of lines in the markdown document.
---@param opts obsidian.note.InsertTextOpts Options for constraining where text can be inserted into the document.
---@return integer insert_idx where new text should be inserted to satisfy the constraints, or `0` when impossible.
---@return string[] insert_before holds the lines needed _before_ the text in order to preserve the layout.
---@return string[] insert_after holds the lines needed _after_ the text in order to preserve the layout.
function M.resolve(lines, opts)
  local line_details = H.get_line_details(lines)
  local sections = H.collapse_into_sections(line_details)
  local section_idx = H.find_desired_section(sections, opts)

  if section_idx > 0 then
    return H.expand_old_section(sections, section_idx, opts)
  end

  local key = opts.section.on_missing or "create"
  local on_missing_handler = assert(H.on_missing_handler[key], "unsupported `opts.section.on_missing` option: " .. key)
  return on_missing_handler(sections, opts)
end

--- Produces detail records for each line in the markdown document that meaningfully contributes to the document layout.
--- Headings defined within codeblock fences (```) will _not_ contribute to the document layout.
---
---@param lines string[] The list of lines in the markdown document.
---@return LineDetail[] line_details for each line in the markdown document.
function H.get_line_details(lines)
  local line_details = {}
  local within_code_block = false

  local function categorize_ith_line_using_early_return_statements(idx)
    local line_str = vim.trim(lines[idx])

    if within_code_block then
      within_code_block = not line_str:match(CODE_BLOCK_PATTERN)
      return { type = "code" }
    elseif line_str:match(CODE_BLOCK_PATTERN) then
      within_code_block = true
      return { type = "code" }
    end

    if line_str == "" then
      return { type = "empty" }
    end

    local level_str, label_str = line_str:match(HEADER_PREFIX_PATTERN)
    if level_str and label_str and level_str ~= "" and label_str ~= "" then
      return { type = "header", level = level_str:len(), label = label_str }
    end

    local prev_line = idx > 1 and line_details[idx - 1] or { type = "empty" }
    local level = (line_str:match(H1_UNDERLINE_PATTERN) and 1) or (line_str:match(H2_UNDERLINE_PATTERN) and 2)
    if level and prev_line.type == "text" then
      line_details[idx - 1] = { type = "header", level = level, label = prev_line.text }
      return { type = "header-underline" }
    end

    return { type = "text", text = line_str }
  end

  for idx = 1, #lines do
    line_details[idx] = categorize_ith_line_using_early_return_statements(idx)
  end

  return line_details
end

--- Collapses lines into a list of "sections". Each section is itself composed of two sub-sections: heading and content.
--- The heading and content sub-sections are defined using a half-open `[beg_incl, end_excl)` range. When empty, they
--- will use values such that `beg_incl == end_excl`.
---
--- IMPORTANT: There will always be AT LEAST TWO sections.
---
--- The FIRST section is the PREAMBLE. It contains the non-empty lines _before_ the first heading. If there aren't any
--- headings, then it will contain ALL non-empty lines in the file. Otherwise, when the document is empty or when the
--- first line in the document is a heading, then the content section of the preamble will be empty.
---
--- The FINAL section is the EOF-MARKER. Both its heading and content is always empty. This section can be used to find
--- the final lines in the document.
---
---@param line_details LineDetail[] The list of details categorizing each line in the document.
---@return SectionDetail[] sections defining the document. There will always be at least two items.
function H.collapse_into_sections(line_details)
  local sections = { H.new_section_detail(1, 1) }
  local current = sections[1]
  local current_content_is_empty = true

  for idx_incl, ith_line in ipairs(line_details) do
    local idx_excl = idx_incl + 1

    if ith_line.type == "header" then
      table.insert(sections, H.new_section_detail(idx_incl, idx_excl, ith_line.level, ith_line.label))
      current = sections[#sections]
      current_content_is_empty = true
    elseif ith_line.type == "header-underline" then
      current.heading.end_excl = idx_excl
      current.content.beg_incl = idx_excl
      current.content.end_excl = idx_excl
    elseif ith_line.type ~= "empty" then
      if current_content_is_empty then
        current.content.beg_incl = idx_incl
        current_content_is_empty = false
      end
      current.content.end_excl = idx_excl
    end
  end

  local eof_excl = current.content.end_excl
  table.insert(sections, H.new_section_detail(eof_excl, eof_excl))

  return sections
end

--- Finds the section index where text should be inserted.
---
---@param sections SectionDetail[] List of sections in the document. Must contain preamble and eof-marker.
---@param opts obsidian.note.InsertTextOpts Options for constraining where text can be inserted into the document.
---@return integer section_idx where the the new text can be inserted while maintaining the layout, or `0` if not found.
function H.find_desired_section(sections, opts)
  if not opts.section then
    return 1
  end

  for idx = 2, #sections - 1 do
    if sections[idx].heading.label == opts.section.header and sections[idx].heading.level == opts.section.level then
      return idx
    end
  end

  return 0
end

---@type fun(beg_incl: integer, end_excl: integer, level?: integer, label?: string): SectionDetail
function H.new_section_detail(beg_incl, end_excl, level, label)
  return {
    heading = { beg_incl = beg_incl, end_excl = end_excl, level = level or 0, label = label or "" },
    content = { beg_incl = end_excl, end_excl = end_excl },
  }
end

---@type table<string, OnMissingHandler>
H.on_missing_handler = {
  abort = function(_, _)
    return 0, {}, {}
  end,

  error = function(_, opts)
    error(string.format("Failed to find the section: %s", vim.inspect(opts.section.header)))
  end,

  create = function(sections, opts)
    -- NOTE: This is an arbitrary choice. Users might want more control over where new sections get positioned.
    local create_at_idx = opts.placement == "bot" and #sections or 2
    return H.create_new_section(sections, create_at_idx, opts)
  end,
}

--- Creates a new heading and section at the specified index and then "pushes down" the section that is currently there.
---
--- Assumes that `index > 1` because the preamble is _defined_ as the lines above all of the other headings in the file.
---
---@param sections SectionDetail[] List of sections in the document. Must contain preamble and eof-marker.
---@param section_idx integer The index where the new section will be inserted. Must NOT be the preamble (at `1`).
---@param opts obsidian.note.InsertTextOpts Options for constraining where text can be inserted into the document.
---@return integer insert_idx where new text should be inserted to satisfy the constraints.
---@return string[] insert_before holds the lines needed _before_ the text in order to preserve the layout.
---@return string[] insert_after holds the lines needed _after_ the text in order to preserve the layout.
function H.create_new_section(sections, section_idx, opts)
  assert(section_idx > 1, "the preamble cannot have headers placed before it.")

  local section = sections[section_idx]
  local prev_section = sections[section_idx - 1]

  local insert_idx = section.heading.beg_incl
  local insert_before = { string.rep("#", opts.section.level) .. " " .. opts.section.header, "" }
  local insert_after = {}

  if not H.is_section_empty(prev_section) and prev_section.content.end_excl == insert_idx then
    table.insert(insert_before, 1, "")
  end

  if not H.is_section_empty(section) then
    table.insert(insert_after, 1, "")
  end

  return insert_idx, insert_before, insert_after
end

--- Expands the section positioned at the specified index so that it can have more text inserted into it.
---
--- Assumes that `index < #sections` because the EOF marker is _defined_ as the empty section of the bottom of the file.
---
---@param sections SectionDetail[] List of sections in the document. Must contain preamble and eof-marker.
---@param section_idx integer The index where the old section is located. Must NOT be the EOF marker (at `#sections`).
---@param opts obsidian.note.InsertTextOpts Options for constraining where text can be inserted into the document.
---@return integer insert_idx where new text should be inserted to satisfy the constraints.
---@return string[] insert_before holds the lines needed _before_ the text in order to preserve the layout.
---@return string[] insert_after holds the lines needed _after_ the text in order to preserve the layout.
function H.expand_old_section(sections, section_idx, opts)
  assert(section_idx < #sections, "the EOF marker cannot have content placed after it.")

  local section = sections[section_idx]
  local next_section = sections[section_idx + 1]

  local insert_idx = opts.placement == "top" and section.content.beg_incl or section.content.end_excl
  local insert_before = {}
  local insert_after = {}

  if H.is_content_empty(section) then
    table.insert(insert_before, 1, "")
  end

  if not H.is_section_empty(next_section) and next_section.heading.beg_incl == insert_idx then
    table.insert(insert_after, 1, "")
  end

  return insert_idx, insert_before, insert_after
end

---@type fun(section: SectionDetail): boolean
function H.is_section_empty(section)
  return not section or section.heading.beg_incl == section.content.end_excl
end

---@type fun(section: SectionDetail): boolean
function H.is_content_empty(section)
  return not section or section.content.beg_incl == section.content.end_excl
end

---@alias (exact) OnMissingHandler fun(sections: SectionDetail[], opts: obsidian.note.InsertTextOpts): insert_idx: integer, insert_before: string[], insert_after: string[]

---@class (exact) SectionDetail
---@field heading? { beg_incl: integer, end_excl: integer, level: integer, label: string }
---@field content? { beg_incl: integer, end_excl: integer }

---@alias (exact) LineDetail
---|LineTextDetail
---|LineHeaderDetail
---|LineHeaderUnderlineDetail
---|LineCodeDetail
---|LineEmptyDetail

---@class (exact) LineTextDetail
---@field type 'text'
---@field text string

---@class (exact) LineHeaderDetail
---@field type 'header'
---@field level integer
---@field label string

---@class (exact) LineHeaderUnderlineDetail
---@field type 'header-underline'

---@class (exact) LineCodeDetail
---@field type 'code'

---@class (exact) LineEmptyDetail
---@field type 'empty'

return M
