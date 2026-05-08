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

--- TODO: use in definition handler later,

---@param location string
---@param current_dir obsidian.Path|?
---@return string|?
local function resolve_strict(location, current_dir)
  local location_path = Path.new(location)
  local has_sep = location:find("/", 1, true) ~= nil

  if location_path:is_absolute() or has_sep then
    local candidates = {}
    if location_path:is_absolute() then
      candidates[#candidates + 1] = location_path
    else
      if current_dir then
        candidates[#candidates + 1] = current_dir / location
      end
      candidates[#candidates + 1] = Obsidian.dir / location
    end
    for _, c in ipairs(candidates) do
      local norm = normalize_path(c)
      if norm:is_file() or norm:is_dir() then
        return tostring(norm)
      end
      if not vim.endswith(tostring(norm), ".md") then
        local with_md = Path.new(tostring(norm) .. ".md")
        if with_md:is_file() then
          return tostring(with_md)
        end
      end
    end
    return nil
  end

  local notes = search.find_notes(location, {})
  if vim.tbl_isempty(notes) then
    return nil
  end

  local loc_lwr = string.lower(location)
  local loc_lwr_md = vim.endswith(loc_lwr, ".md") and loc_lwr or (loc_lwr .. ".md")
  local pool = {}

  for _, note in ipairs(notes) do
    local stem = note.path and note.path.stem and string.lower(note.path.stem) or ""
    local name = note.path and note.path.name and string.lower(note.path.name) or ""
    if stem == loc_lwr or name == loc_lwr or name == loc_lwr_md then
      pool[#pool + 1] = note
    end
  end

  if #pool == 0 then
    return nil
  end

  if current_dir then
    local cur_key = tostring(normalize_path(current_dir))
    for _, n in ipairs(pool) do
      if tostring(normalize_path(n.path:parent())) == cur_key then
        return tostring(n.path)
      end
    end
  end

  local vault_key = tostring(normalize_path(Obsidian.dir))
  for _, n in ipairs(pool) do
    if tostring(normalize_path(n.path:parent())) == vault_key then
      return tostring(n.path)
    end
  end

  return tostring(pool[1].path)
end

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

  local current_path = vim.api.nvim_buf_get_name(0)
  local current_dir = current_path ~= "" and Path.new(vim.fs.dirname(current_path)) or nil

  if Obsidian.opts.link and Obsidian.opts.link.resolve == "strict" then
    return resolve_strict(location, current_dir)
  end

  local location_path = Path.new(location)
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
    local parsed_location = util.parse_link(link, { exclude = { "Tag", "BlockID" } })
    location = parsed_location or location
  end

  if not location then
    return
  end

  location = vim.uri_decode(location)
  return M.resolve_link_path(location)
end

return M
