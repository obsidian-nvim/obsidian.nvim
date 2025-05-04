local abc = require "obsidian.abc"
local search = require "obsidian.search"
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

  require("obsidian.filewatch").watch(client.dir.filename, {
    on_event = function(filename, events)
      vim.print(filename .. "changed!")
    end,
  }, {
    watch_entry = true,
    recursive = true,
  })

  return self
end

--- Reads all notes in the vaults and returns filename of each note relative to the vault and note's aliases.
---@param client obsidian.Client
local get_links_from_vault = function(client)
  local interator = search.find(client.dir, "", nil)

  local founded_aliases = {}

  local notepath = interator()

  while notepath do
    local note = Note.from_file(notepath, { read_only_frontmatter = true })

    local relative_path = note.path.filename:gsub(client.dir.filename .. "/", "")
    local note_cache = { relative_path, note.aliases }

    table.insert(founded_aliases, note_cache)

    notepath = interator()
  end

  return founded_aliases
end

Cache.index_vault = function(self)
  local ok, founded_links = pcall(get_links_from_vault, self.client)

  if not ok then
    error "couldn't get links from vault"
  end

  local file, err = io.open("./temp.json", "w")

  if file then
    file:write(vim.fn.json_encode(founded_links))
    file:close()
  else
    error("couldn't write vault index to file: " .. err)
  end
end

Cache.get_links_from_cache = function(self)
  local file, err = io.open("./temp.json", "r")

  if file then
    local links_json = file:read()
    file:close()
    return vim.fn.json_decode(links_json)
  else
    error("couldn't read vault index to file: " .. err)
  end
end

return Cache
