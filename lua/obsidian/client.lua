--- *obsidian-api*
---
--- The Obsidian.nvim Lua API.
---
--- ==============================================================================
---
--- Table of contents
---
---@toc

local log = require "obsidian.log"

---@class obsidian.SearchOpts
---
---@field sort boolean|?
---@field include_templates boolean|?
---@field ignore_case boolean|?
---@field default function?

--- The Obsidian client is the main API for programmatically interacting with obsidian.nvim's features
--- in Lua. To get the client instance, run:
---
--- `local client = require("obsidian").get_client()`
---
---@toc_entry obsidian.Client
---
---@class obsidian.Client : obsidian.ABC
local Client = {}

local depreacted_lookup = {
  dir = "dir",
  buf_dir = "buf_dir",
  current_workspace = "workspace",
  opts = "opts",
}

Client.__index = function(_, k)
  if depreacted_lookup[k] then
    local msg = string.format(
      [[client.%s is depreacted, use Obsidian.%s instead.
client is going to be removed in the future as well.]],
      k,
      depreacted_lookup[k]
    )
    log.warn(msg)
    return Obsidian[depreacted_lookup[k]]
  elseif rawget(Client, k) then
    return rawget(Client, k)
  end
end

--- Create a new Obsidian client without additional setup.
--- This is mostly used for testing. In practice you usually want to obtain the existing
--- client through:
---
--- `require("obsidian").get_client()`
---
---@return obsidian.Client
Client.new = function()
  return setmetatable({}, Client)
end

return Client
