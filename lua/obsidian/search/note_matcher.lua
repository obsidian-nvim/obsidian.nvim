local filetypes = require "obsidian.filetypes"
local fs_util = require "obsidian.util.fs"

local M = {}

---@class obsidian.search.NoteMatchOpts
---@field references boolean|? Match note IDs, aliases, filenames, and relative paths. Defaults to true.
---@field headings boolean|? Match heading text and normalized anchors.
---@field blocks boolean|? Match block text and block IDs.

---Build the note parser options needed by a note search.
---
---`match` controls which domains are searched and guarantees that those
---domains are present on returned notes. `collect` adds result data without
---changing which notes match.
---@param opts obsidian.search.FindNotesOpts
---@return obsidian.note.LoadOpts
function M.parse_opts(opts)
  local headings = (opts.match and opts.match.headings) or (opts.collect and opts.collect.headings)
  local blocks = (opts.match and opts.match.blocks) or (opts.collect and opts.collect.blocks)
  return {
    collect_anchor_links = headings == true,
    collect_blocks = blocks == true,
    collect_block_candidates = blocks == true,
  }
end

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
  if source.anchor_links then
    for anchor, data in pairs(source.anchor_links) do
      add(values, anchor)
      add(values, data.header)
      add(values, data.anchor)
    end
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
---@param opts obsidian.search.NoteMatchOpts|?
---@param ignore_case boolean|?
---@return boolean
function M.matches(path, root, source, query, opts, ignore_case)
  query = vim.trim(query or "")
  if query == "" then
    return true
  end

  opts = opts or {}
  local match_references = opts.references ~= false
  ignore_case = ignore_case == true

  if match_references and any_contains(query, reference_values(path, root, source), ignore_case) then
    return true
  end
  if opts.headings and any_contains(query, heading_values(source), ignore_case) then
    return true
  end
  if opts.blocks and any_contains(query, block_values(source), ignore_case) then
    return true
  end
  return false
end

M.without_note_extension = without_note_extension
M.reference_values = reference_values

return M
