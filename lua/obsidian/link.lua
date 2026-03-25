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

--- TODO: use in definition handler later?

---@param location string
---@return string|?
M.resolve_link_path = function(location)
  local is_uri = util.is_uri(location)
  if is_uri then
    return nil
  end

  local block_link, anchor_link
  location, block_link = util.strip_block_links(location)
  location, anchor_link = util.strip_anchor_links(location)

  if location == "" then
    local current_path = vim.api.nvim_buf_get_name(0)
    if current_path ~= "" then
      return tostring(normalize_path(current_path))
    end
    return nil
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

  local notes = search.resolve_note(location, {
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })
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
    local parsed_location, _, _link_type = util.parse_link(link, { exclude = { "Tag", "BlockID" } })
    location = parsed_location or location
  end

  if not location then
    return
  end

  location = vim.uri_decode(location)
  local res = M.resolve_link_path(location)
  return res
end

return M
