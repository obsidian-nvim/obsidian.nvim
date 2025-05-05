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
      -- TODO get the full path without async
      local full_path = client:resolve_note(filename)
      vim.print(full_path)

      -- TODO update the cache for the updated file
      -- TODO implement fast search of the note
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

  --TODO add updated progress
  local note_amount = 0
  while notepath do
    local note = Note.from_file(notepath, { read_only_frontmatter = true })

    local relative_path = note.path.filename:gsub(client.dir.filename .. "/", "")
    -- TODO: add last update time to updated notes that were updated when neovim was offline
    -- TODO add typing
    local note_cache = { note.path.filename, note.aliases, relative_path }

    table.insert(founded_aliases, note_cache)

    notepath = interator()

    note_amount = note_amount + 1
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
  -- TODO: allow change the save location and use hidden name
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
