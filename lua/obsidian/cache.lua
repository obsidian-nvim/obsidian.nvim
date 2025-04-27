local is_sqlite_available, sqlite = pcall(require, "sqlite")
local abc = require "obsidian.abc"
local Note = require "obsidian.note"

---@class obsidian.Cache : obsidian.ABC
---
---@field client obsidian.Client
local Cache = abc.new_class()

--- Cache description
---
---@param client obsidian.Client
Cache.new = function(client)
  local self = Cache.init()
  self.client = client

  return self
end

Cache.index_vault = function(self)
  local notes = self.client:find_notes("zettel", { search = { sort = false } })
  vim.print(vim.inspect(notes))
end

return Cache
