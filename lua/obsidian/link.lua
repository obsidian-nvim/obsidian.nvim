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
    return tostring(normalize_path(attachment._resolve(location)))
  end

  local current_path = vim.api.nvim_buf_get_name(0)
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
---@return string|?
---@return obsidian.Range|?
M.includeexpr = function()
  local link = api.cursor_link()
  local location, range
  local row = unpack(vim.api.nvim_win_get_cursor(0)) - 1 -- 0-indexed row

  if link then
    local parsed_location, _, _, parsed_range = util.parse_link(link, { row = row })
    location = parsed_location
    range = parsed_range
  end

  if not location then
    return
  end

  local decoded = vim.uri_decode(location)
  if decoded then
    ---@cast decoded string
    location = decoded
  end
  return M.resolve_link_path(location), range
end

return M
