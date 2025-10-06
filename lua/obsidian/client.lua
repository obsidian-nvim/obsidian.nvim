local log = require "obsidian.log"

---@class obsidian.Client : obsidian.ABC
local Client = {}

local deprecated_lookup = {
  dir = "dir",
  buf_dir = "buf_dir",
  current_workspace = "workspace",
  opts = "opts",
}

Client.__index = function(_, k)
  if deprecated_lookup[k] then
    local msg = string.format(
      [[client.%s is deprecated, use Obsidian.%s instead.
client is going to be removed in the future as well.]],
      k,
      deprecated_lookup[k]
    )
    log.warn(msg)
    return Obsidian[deprecated_lookup[k]]
  elseif rawget(Client, k) then
    return rawget(Client, k)
  end
end

---@return obsidian.Client
Client.new = function()
  return setmetatable({}, Client)
end

return Client
