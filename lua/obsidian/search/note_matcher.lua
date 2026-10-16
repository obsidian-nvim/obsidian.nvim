local filetypes = require "obsidian.filetypes"
local fs_util = require "obsidian.util.fs"

local M = {}

---@param path string
---@return string
local function without_note_extension(path)
  if filetypes.is_note(path) then
    return (path:gsub("%.[^./\\]+$", ""))
  end
  return path
end

---@param values string[]
---@param value any
local function add(values, value)
  if value ~= nil then
    value = tostring(value)
    if value ~= "" then
      values[#values + 1] = value
    end
  end
end

---@param path string
---@param root string
---@param source table
---@return string[]
local function reference_values(path, root, source)
  local values = {}
  local rel = fs_util.relpath(root, path) or path
  add(values, path)
  add(values, without_note_extension(path))
  add(values, rel)
  add(values, without_note_extension(rel))
  add(values, vim.fs.basename(path))
  add(values, without_note_extension(vim.fs.basename(path)))
  add(values, source.id)
  add(values, source.title)
  if source.display_name and type(source.display_name) == "function" then
    add(values, source:display_name())
  end
  for _, alias in ipairs(source.aliases or {}) do
    add(values, alias)
  end
  return values
end

---@param source table
---@return string[]
local function heading_values(source)
  local values = {}
  for _, heading in ipairs(source.headings or {}) do
    add(values, heading.header)
    add(values, heading.anchor)
  end
  for _, section in ipairs(source.sections or {}) do
    add(values, section.header)
    add(values, section.anchor)
  end
  return values
end

---@param source table
---@return string[]
local function block_values(source)
  local values = {}
  for _, value in ipairs(source.blocks_search or {}) do
    add(values, value)
  end
  for id, block in pairs(source.blocks or {}) do
    add(values, id)
    add(values, block.id)
    add(values, block.block)
  end
  if source.contents then
    for _, section in ipairs(source.block_candidates or {}) do
      local lines = vim.list_slice(source.contents, section.range.start_row + 1, section.range.end_row)
      add(values, table.concat(lines, "\n"))
    end
  end
  return values
end

---@param query string
---@param values string[]
---@param ignore_case boolean
---@return boolean
local function any_contains(query, values, ignore_case)
  if ignore_case then
    query = string.lower(query)
  end
  for _, value in ipairs(values) do
    if ignore_case then
      value = string.lower(value)
    end
    if string.find(value, query, 1, true) ~= nil then
      return true
    end
  end
  return false
end

---Match a normalized note or cache row against the structured note-search domains.
---@param path string
---@param root string
---@param source table obsidian.Note or obsidian.cache.NoteRow
---@param query string
---@param domain obsidian.search.NoteSearchDomain|?
---@param ignore_case boolean|?
---@return boolean
function M.matches(path, root, source, query, domain, ignore_case)
  query = vim.trim(query or "")
  if query == "" then
    return true
  end

  domain = domain or "references"
  ignore_case = ignore_case == true
  if domain == "references" then
    return any_contains(query, reference_values(path, root, source), ignore_case)
  elseif domain == "headings" then
    return any_contains(query, heading_values(source), ignore_case)
  elseif domain == "blocks" then
    return any_contains(query, block_values(source), ignore_case)
  end
  return false
end

---@param section obsidian.Section
---@return string[]
local function section_values(section)
  return { section.header, section.anchor }
end

---Return matching heading anchors, with one result per heading section.
---@param note obsidian.Note
---@param query string
---@param ignore_case boolean
---@return obsidian.note.HeaderAnchor[]
function M.matching_headings(note, query, ignore_case)
  query = vim.trim(query or "")
  local matches = {}
  for _, section in ipairs(note.sections or {}) do
    if section.header and any_contains(query, section_values(section), ignore_case) then
      local heading = note.anchor_links and note.anchor_links[section.anchor]
      if not heading then
        heading = {
          anchor = section.anchor,
          header = section.header,
          level = section.level,
          line = section.heading_range.start_row + 1,
          section = section,
        }
      end
      matches[#matches + 1] = heading
    end
  end
  return matches
end

---@param note obsidian.Note
---@param section obsidian.Section
---@return string
local function section_text(note, section)
  local contents = section.cached_contents
  if contents == nil and note.contents then
    contents = vim.list_slice(note.contents, section.range.start_row + 1, section.range.end_row)
  end
  return table.concat(contents or {}, "\n")
end

---Return matching block candidates and explicit block identifiers.
---@param note obsidian.Note
---@param query string
---@param ignore_case boolean
---@return obsidian.search.BlockMatch[]
function M.matching_blocks(note, query, ignore_case)
  query = vim.trim(query or "")
  local result = {}
  ---@type table<obsidian.Section, obsidian.note.Block[]>
  local blocks_by_section = {}
  ---@type obsidian.note.Block[]
  local orphan_blocks = {}
  ---@type table<string, obsidian.note.Block>
  local blocks = note.blocks or {}
  ---@type string[]
  local block_ids = vim.tbl_keys(blocks)
  table.sort(block_ids)

  for _, id in ipairs(block_ids) do
    local block = assert(blocks[id], "block row is missing")
    if block.section then
      local section_blocks = blocks_by_section[block.section] or {}
      section_blocks[#section_blocks + 1] = block
      blocks_by_section[block.section] = section_blocks
    else
      orphan_blocks[#orphan_blocks + 1] = block
    end
  end

  local candidate_sections = {}
  for _, section in ipairs(note.block_candidates or {}) do
    candidate_sections[section] = true
    local section_blocks = blocks_by_section[section] or {}
    local values = { section_text(note, section) }
    for _, block in ipairs(section_blocks) do
      values[#values + 1] = block.id
      values[#values + 1] = block.block
    end
    if any_contains(query, values, ignore_case) then
      result[#result + 1] = {
        note = note,
        section = section,
        blocks = section_blocks,
      }
    end
  end

  local emitted_sections = {}
  for _, id in ipairs(block_ids) do
    local section = assert(blocks[id], "block row is missing").section
    if section and not candidate_sections[section] and not emitted_sections[section] then
      emitted_sections[section] = true
      local section_blocks = assert(blocks_by_section[section], "section blocks are missing")
      local values = {}
      for _, block in ipairs(section_blocks) do
        values[#values + 1] = block.id
        values[#values + 1] = block.block
      end
      if any_contains(query, values, ignore_case) then
        result[#result + 1] = {
          note = note,
          section = section,
          blocks = section_blocks,
        }
      end
    end
  end

  for _, block in ipairs(orphan_blocks) do
    if any_contains(query, { block.id, block.block }, ignore_case) then
      result[#result + 1] = {
        note = note,
        blocks = { block },
      }
    end
  end
  return result
end

M.without_note_extension = without_note_extension
M.reference_values = reference_values

return M
