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
---@param source_path string|? path of the note containing the link, used to resolve relative paths.
---@return string|?
M.resolve_link_path = function(location, source_path)
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
    local path = attachment._resolve(location, { filename = source_path })
    if path then
      return tostring(normalize_path(path))
    end
    return nil
  end

  local current_path = source_path or vim.api.nvim_buf_get_name(0)
  local current_dir = current_path ~= "" and vim.fs.dirname(current_path) or nil
  local workspace_dir = api.resolve_workspace_dir(current_path ~= "" and current_path or nil)

  local notes = search.resolve_note(location, {
    dir = workspace_dir,
    buf_dir = current_dir,
  })

  if not vim.tbl_isempty(notes) and notes[1] ~= nil then
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

  local decoded = vim.uri_decode(location)
  if decoded then
    ---@cast decoded string
    location = decoded
  end
  return M.resolve_link_path(location)
end

return M
