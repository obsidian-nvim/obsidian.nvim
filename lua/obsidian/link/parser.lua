local uri = require "obsidian.uri"

local M = {}

--- Split a note-link destination into its location and fragment components.
--- Returned anchors omit `#`; returned block IDs omit `#^`.
--- URI fragments are kept as part of the URI.
---@param value string
---@return string location
---@return string? anchor
---@return string? block
M.parse = function(value)
  if uri.is_uri(value) then
    return value, nil, nil
  end

  local hash = value:find("#", 1, true)
  if not hash then
    return value, nil, nil
  end

  local location = value:sub(1, hash - 1)
  local fragment = value:sub(hash + 1)
  if fragment:sub(1, 1) == "^" then
    return location, nil, fragment:sub(2)
  end
  return location, fragment, nil
end

--- Join a location and one optional fragment.
---@param location string
---@param anchor? string
---@param block? string
---@return string
M.format = function(location, anchor, block)
  assert(anchor == nil or block == nil, "a link cannot have both an anchor and a block")
  if block ~= nil then
    block = block:gsub("^#", ""):gsub("^%^", "")
    return location .. "#^" .. block
  elseif anchor ~= nil then
    return location .. "#" .. anchor:gsub("^#+", "")
  end
  return location
end

return M
