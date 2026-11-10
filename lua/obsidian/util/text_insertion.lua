local Section = require "obsidian.section"
local Range = require "obsidian.range"

local M = {}
local H = {}

---@alias obsidian.note.OnSectionMissingHandler fun(sections: obsidian.Section[], opts: obsidian.note.InsertTextOpts): insert_idx: integer, insert_top: string[], insert_bot: string[]

--- Resolves the changes needed to insert text into the given markdown document while preserving the given constraints.
---
---@param lines string[] The list of lines in the markdown document.
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer insert_idx where new text should be inserted to satisfy the constraints, or `0` when impossible.
---@return string[] insert_top holds the lines needed _before_ the text in order to preserve the constraints.
---@return string[] insert_bot holds the lines needed _after_ the text in order to preserve the constraints.
---@return obsidian.Range? content_range Target extent for explicit spacing.
function M.resolve(lines, opts)
  if opts.target == "body" then
    return opts.placement == "bot" and #lines + 1 or 1, {}, {}, Range.new(0, 0, #lines, 0)
  end

  local sections = H.parse_sections(lines)
  local chosen_idx = H.choose_section(sections, opts)

  if chosen_idx > 0 then
    local section = sections[chosen_idx]
    ---@cast section -nil
    if opts.spacing then
      local first = section.header and section.heading_range.end_row or section.content_range.start_row
      while true do
        local line = lines[first + 1]
        if not line or vim.trim(line) ~= "" then
          break
        end
        first = first + 1
      end
      local last = opts.include_children and section.range.end_row or section.content_range.end_row
      last = math.max(first, last)
      return opts.placement == "bot" and last + 1 or first + 1, {}, {}, Range.new(first, 0, last, 0)
    end
    return H.expand_old_section(sections, chosen_idx, opts)
  else
    local key = opts.on_section_missing or "create"
    local handler = H.on_section_missing_handlers[key]
    ---@cast handler obsidian.note.OnSectionMissingHandler
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

---@param choice obsidian.note.insert_text.SectionChoice
---@return { header: string?, level: integer? }
local function normalize_section_choice(choice)
  if type(choice) == "table" then
    local header, level = choice.header or choice[1], choice.level or choice[2]
    assert(header == nil or type(header) == "string", "section.header must be string or nil")
    assert(level == nil or type(level) == "number", "section.level must be number or nil")
    return { header = header, level = level }
  elseif type(choice) == "string" then
    return { header = choice }
  elseif type(choice) == "number" then
    return { level = choice }
  elseif choice == nil then
    return {}
  else
    error("invalid section: " .. vim.inspect(choice))
  end
end

--- Chooses a section to insert new text into.
---
---@param sections obsidian.Section[] List of sections in the document. Must contain the preamble and EOF-marker.
---@param opts obsidian.note.InsertTextOpts Constrains where text can be inserted.
---@return integer chosen_idx where the new text can be inserted while maintaining the layout, or `0` if none are valid.
function H.choose_section(sections, opts)
  local section_opts = normalize_section_choice(opts.section)
  local header_wanted = section_opts.header
  local level_wanted = section_opts.level

  if not header_wanted and not level_wanted then
    return 1
  end

  if header_wanted and opts.ignore_case then
    header_wanted = vim.fn.tolower(header_wanted)
  end

  for idx = 2, #sections - 1 do
    local section = sections[idx]
    ---@cast section -nil
    local header = section.header
    if header and opts.ignore_case then
      header = vim.fn.tolower(header)
    end
    if (not header_wanted or header == header_wanted) and (not level_wanted or section.level == level_wanted) then
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
  ---@cast section_chosen -nil
  ---@cast section_after -nil

  local insert_idx = opts.placement == "top" and beg_incl(section_chosen.content_range)
    or end_excl(section_chosen.content_range)
  if opts.placement == "bot" and opts.include_children then
    insert_idx = end_excl(section_chosen.range)
    for idx = chosen_idx + 1, #sections do
      local candidate = sections[idx]
      if beg_incl(candidate.heading_range) >= insert_idx then
        section_after = candidate
        break
      end
    end
  end
  local insert_top = {}
  local insert_bot = {}

  local has_children = opts.include_children and section_chosen.range.end_row > section_chosen.heading_range.end_row
  if H.is_content_empty(section_chosen) and not has_children then
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
  ---@cast section_chosen -nil
  ---@cast section_before -nil

  local insert_idx = beg_incl(section_chosen.heading_range)
  local insert_top = {}
  local insert_bot = {}

  if
    (not H.is_section_empty(section_before) or opts.padding_top)
    and end_excl(section_before.content_range) == insert_idx
  then
    table.insert(insert_top, "")
  end

  local section_opts = normalize_section_choice(opts.section)
  table.insert(insert_top, string.rep("#", section_opts.level or 2) .. " " .. (section_opts.header or "Untitled"))
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
    local section_opts = normalize_section_choice(opts.section)
    error("Failed to find section: " .. vim.inspect { header = section_opts.header, level = section_opts.level })
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

--- Join text with at least the requested separation, preserving existing padding.
---@param left string
---@param right string
---@param spacing string
---@return string
local function join(left, right, spacing)
  if left == "" or right == "" then
    return left .. right
  end
  local required = spacing == "inline" and 0 or (spacing == "newline" and 1 or 2)
  local trailing = #(left:match "\n*$" or "")
  local leading = #(right:match "^\n*" or "")
  return left .. string.rep("\n", math.max(0, required - trailing - leading)) .. right
end

--- Apply an insertion to body lines. Positions are 1-based rows and 0-based byte columns.
--- A cancelled or empty insertion returns position 0, 0.
---@param lines string[]
---@param text string|string[]
---@param opts obsidian.note.InsertTextOpts
---@return string[] lines
---@return integer row
---@return integer col
function M.apply(lines, text, opts)
  assert(opts.spacing == nil or vim.list_contains({ "auto", "newline", "inline" }, opts.spacing), "Invalid spacing")
  local incoming
  if type(text) == "string" then
    incoming = text == "" and {} or vim.split(text, "\n", { plain = true })
  else
    incoming = text
  end
  local idx, top, bot, extent = M.resolve(lines, opts)
  if idx == 0 or #incoming == 0 then
    return lines, 0, 0
  end

  if not opts.spacing or not extent then
    local out = vim.list_slice(lines, 1, idx - 1)
    for _, group in ipairs { top, incoming, bot, vim.list_slice(lines, idx) } do
      vim.list_extend(out, group)
    end
    return out, idx + #top, 0
  end

  local first, last = extent.start_row, extent.end_row
  local body = table.concat(vim.list_slice(lines, first + 1, last), "\n")
  local content = table.concat(incoming, "\n")
  local before = ""
  if opts.placement == "bot" then
    body = join(body, content, opts.spacing)
    before = body:sub(1, #body - #content)
  else
    body = join(content, body, opts.spacing)
  end

  local prefix = vim.list_slice(lines, 1, first)
  local suffix = vim.list_slice(lines, last + 1)
  if
    opts.placement == "bot"
    and opts.spacing == "auto"
    and body:sub(-1) ~= "\n"
    and vim.trim(suffix[1] or "") ~= ""
  then
    table.insert(suffix, 1, "")
  end
  vim.list_extend(prefix, vim.split(body, "\n", { plain = true }))
  vim.list_extend(prefix, suffix)
  local preceding = vim.split(before, "\n", { plain = true })
  return prefix, first + #preceding, #preceding[#preceding]
end

return M
