local Path = require "obsidian.path"
local util = require "obsidian.util"
local search = require "obsidian.search"
local attachment = require "obsidian.attachment"
local api = require "obsidian.api"

local M = {}

---@param path string|obsidian.Path
---@return obsidian.Path
local function normalize_path(path)
  return Path.new(path):resolve()
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param location string
---@param source_file string|?
---@return string|?
local function missing_attachment_path(location, source_file)
  local target = normalize_link_target(location)
  if target == "" then
    return nil
  end

  if target:find("/", 1, true) then
    local source_dir = source_file and source_file ~= "" and Path.new(vim.fs.dirname(source_file)) or nil
    local candidates = {}
    if source_dir then
      candidates[#candidates + 1] = source_dir / target
    end
    candidates[#candidates + 1] = Obsidian.dir / target

    for _, candidate in ipairs(candidates) do
      local abs = vim.fs.normalize(tostring(candidate:resolve()))
      if util.is_subpath(abs, tostring(Obsidian.dir)) then
        return abs
      end
    end
    return nil
  end

  return vim.fs.normalize(attachment.resolve_attachment_path(target, source_file))
end

---@param location string
---@return string|?
local function missing_note_path(location)
  local target = normalize_link_target(location)
  if target == "" then
    return nil
  end

  local Note = require "obsidian.note"
  local note = Note.create { id = target }
  return vim.fs.normalize(tostring(note.path))
end

--- Expected absolute path for a link target that does not exist yet.
---
---@param location string
---@param source_file string|? Absolute path to the note containing the link.
---@return string|?
M.missing_link_path = function(location, source_file)
  if util.is_uri(location) then
    return nil
  end

  location = util.strip_block_links(location)
  location = util.strip_anchor_links(location)

  if location == "" then
    return
  end

  if attachment.is_attachment_path(location) then
    return missing_attachment_path(location, source_file)
  end

  return missing_note_path(location)
end

--- TODO: use in definition handler later,

---@param location string
---@return string|?
M.resolve_link_path = function(location)
  local is_uri = util.is_uri(location)
  if is_uri then
    return nil
  end

  location = util.strip_block_links(location)
  location = util.strip_anchor_links(location)

  if location == "" then
    return
  end

  if attachment.is_attachment_path(location) then
    return tostring(normalize_path(M.resolve_attachment_path(location)))
  end

  local location_path = Path.new(location)
  local current_path = vim.api.nvim_buf_get_name(0)
  local current_dir = current_path ~= "" and Path.new(vim.fs.dirname(current_path)) or nil

  local candidates = {}
  local seen = {}

  ---@param path string|obsidian.Path|?
  local add_candidate = function(path)
    if not path then
      return
    end

    local normalized = normalize_path(path)
    local key = tostring(normalized)
    if seen[key] then
      return
    end

    seen[key] = true
    candidates[#candidates + 1] = normalized
  end

  if location_path:is_absolute() then
    add_candidate(location_path)
  else
    if current_dir then
      add_candidate(current_dir / location)
    end
    add_candidate(location_path)
    add_candidate(Obsidian.dir / location)

    if Obsidian.opts.notes_subdir ~= nil then
      add_candidate(Obsidian.dir / Obsidian.opts.notes_subdir / location)
    end

    if Obsidian.opts.daily_notes.folder ~= nil then
      add_candidate(Obsidian.dir / Obsidian.opts.daily_notes.folder / location)
    end
  end

  for _, candidate in ipairs(candidates) do
    if candidate:is_file() or candidate:is_dir() then
      return tostring(candidate)
    end
  end

  local notes = search.find_notes(location, {})
  if not vim.endswith(location:lower(), ".base") then
    notes = vim.tbl_filter(function(note)
      return not vim.endswith(tostring(note.path), ".base")
    end, notes)
  end
  if vim.tbl_isempty(notes) then
    return nil
  elseif #notes == 1 then
    return tostring(notes[1].path)
  elseif #notes > 1 then
    return tostring(notes[1].path)
  end
end

--- For gf and other goto file operations to work.
---@param fname string|?
---@return string|?
M.includeexpr = function(fname)
  local link = api.cursor_link()
  local location = fname

  if link then
    local parsed_location = util.parse_link(link)
    location = parsed_location or location
  end

  if not location then
    return
  end

  location = vim.uri_decode(location)
  return M.resolve_link_path(location)
end

return M
