local abc = require "obsidian.abc"
local search = require "obsidian.search"
local Note = require "obsidian.note"
local log = require "obsidian.log"
local EventTypes = require("obsidian.filewatch").EventTypes
local uv = vim.uv

---This class allows you to find the notes in your vault more quickly.
---It scans your vault and saves the founded metadata to the default cache file ".cache.json"
---in the root of your vault or in the path you specified.
---For example, this allows to search for alises of your
---notes in much shorter time.
---@class obsidian.Cache : obsidian.ABC
---
---@field client obsidian.Client
local Cache = abc.new_class()

---Contains some information from the metadata of your note plus additional info.
---@class obsidian.cache.CacheNote
---
---@field absolute_path string The full path to the note.
---@field relative_path string The relative path to the root of the vault.
---@field aliases string[] The alises of the note founded in the frontmatter.
---@field last_updated number The last time the note was updated in seconds since epoch.

---Converts the links to json and saves to the file at the given path.
---@param links obsidian.cache.CacheNote[]
---@param note_path string|obsidian.Note
local save_cache_notes_to_file = function(links, note_path)
  local save_path

  if type(note_path) == "obsidian.Note" then
    save_path = note_path.path.filename
  else
    save_path = note_path
  end

  local file, err = io.open(save_path, "w")

  if file then
    file:write(vim.fn.json_encode(links))
    file:close()
  else
    error(table.concat { "Couldn't write vault index to the file: ", save_path, ". Description: ", err })
  end
end

---@param self obsidian.Cache
---@return fun (absolute_path: string, event_type: obsidian.filewatch.EventType, stat: uv.fs_stat.result)
local create_on_file_change_callback = function(self)
  return function(filename, event_type, stat)
    vim.schedule(function()
      local founded = false

      local links = self:get_cache_notes_from_file()
      for i, v in ipairs(links) do
        if not v then
          log.warn("empty note cache is founded")
          v = {}
          v.absolute_path = "NAN"
        end
        if v.absolute_path == filename then
          if event_type == EventTypes.deleted then
            table.remove(links, i)
          else
            local note = Note.from_file(filename, { read_only_frontmatter = true })

            local relative_path = note.path.filename:gsub(self.client.dir.filename .. "/", "")

            links[i] = {
              absolute_path = filename,
              aliases = note.aliases,
              relative_path = relative_path,
              last_updated = stat.mtime.sec,
            }
          end

          founded = true
          break
        end
      end

      if not founded then
        -- Unknown file that was deleted is not in the cache, so we don't need to do anything.
        if event_type == EventTypes.deleted then
          return
        end

        local new_note = Note.from_file(filename, { read_only_frontmatter = true })

        local relative_path = new_note.path.filename:gsub(self.client.dir.filename .. "/", "")

        local new_cache = {
          absolute_path = filename,
          aliases = new_note.aliases,
          relative_path = relative_path,
          last_updated = stat.mtime.sec,
        }

        table.insert(links, new_cache)
      end

      save_cache_notes_to_file(links, self.client.opts.cache.cache_path)
    end)
  end
end

---Checks for note cache that were updated outside the vault
---@param self obsidian.Cache
local check_cache_notes_are_fresh = function(self)
  local note_cache_list = self:get_cache_notes_from_file()

  local completed = 0
  local total = #note_cache_list
  local updated = {}
  local on_done = function()
    completed = completed + 1

    if completed == total then
      vim.schedule(function()
        save_cache_notes_to_file(updated, self.client.opts.cache.cache_path)
      end)
    end
  end

  for _, note_cache in ipairs(note_cache_list) do
    uv.fs_stat(note_cache.absolute_path, function(err, stat)
      if err then
        err("Couldn't get stat from the file " .. note_cache.relative_path .. " when performing reindex: " .. err)
      end

      local aliases
      if note_cache.last_updated ~= stat.mtime.sec then
        local note = Note.from_file(note_cache.absolute_path, { read_only_frontmatter = true })
        aliases = note.aliases
      else
        aliases = note_cache.aliases
      end

      ---@type obsidian.cache.CacheNote
      table.insert(updated, {
        absolute_path = note_cache.absolute_path,
        last_updated = stat.mtime.sec,
        aliases = aliases,
        relative_path = note_cache.relative_path,
      })

      on_done()
    end)
  end
end

---Checks that file exits
---@param path string
---@param callback fun (result: boolean)
local check_file_exists = function(path, callback)
  uv.fs_stat(path, function(err, _)
    if not err then
      callback(true)
    else
      callback(false)
    end
  end)
end

---Watches the vault for changes.
---@param self obsidian.Cache
local enable_filewatch = function(self)
  local handlers = require("obsidian.filewatch").watch(self.client.dir.filename, create_on_file_change_callback(self))

  vim.api.nvim_create_autocmd({ "QuitPre", "ExitPre" }, {
    callback = function()
      for _, handle in ipairs(handlers) do
        if handle then
          handle:stop()
          if not handle.is_closing then
            handle:close()
          end
        end
      end
    end,
  })
end

---@param self obsidian.Cache
local check_vault_cache = function(self)
  check_file_exists(self.client.opts.cache.cache_path, function(exists)
    if exists then
      vim.schedule(function()
        check_cache_notes_are_fresh(self)
      end)
    else
      vim.schedule(function()
        self:index_vault()
      end)
    end
  end)
end

---@param client obsidian.Client
Cache.new = function(client)
  local self = Cache.init()
  self.client = client

  if client.opts.cache.enable then
    enable_filewatch(self)

    check_vault_cache(self)
  end

  return self
end

--- Reads all notes in the vaults and returns the founded data.
---@param client obsidian.Client
---@return obsidian.cache.CacheNote[]
local get_cache_notes_from_vault = function(client)
  local interator = search.find(client.dir, "", nil)

  ---@type obsidian.cache.CacheNote[]
  local created_note_caches = {}

  local notepath = interator()

  --TODO add indexing progress
  while notepath do
    local note = Note.from_file(notepath, { read_only_frontmatter = true })

    local absolute_path = note.path.filename
    local relative_path = absolute_path:gsub(client.dir.filename .. "/", "")

    local file_stat = uv.fs_stat(absolute_path)
    local last_updated

    if type(file_stat) ~= "table" then
      log.err(table.concat { "couldn't get file stat from file ", absolute_path })
      last_updated = 0
    else
      last_updated = file_stat.mtime.sec
    end

    ---@type obsidian.cache.CacheNote
    local note_cache = {
      absolute_path = absolute_path,
      aliases = note.aliases,
      relative_path = relative_path,
      last_updated = last_updated,
    }

    table.insert(created_note_caches, note_cache)

    notepath = interator()
  end

  return created_note_caches
end

--- Reads all notes in the vaults and saves them to the cache file.
---@param self obsidian.Cache
Cache.index_vault = function(self)
  if not self.client.opts.cache.enable then
    log.error "The cache is disabled. Cannot index vault."
  end

  local founded_links = get_cache_notes_from_vault(self.client)

  save_cache_notes_to_file(founded_links, self.client.opts.cache.cache_path)

  log.info "Vault was indexed succesfully."
end

---Reads the cache file from client.opts.cache.cache_path and returns founded note cache.
---@param self obsidian.Cache
---@return obsidian.cache.CacheNote[]
Cache.get_cache_notes_from_file = function(self)
  local file, err = io.open(self.client.opts.cache.cache_path, "r")

  if file then
    local links_json = file:read()
    file:close()
    return vim.fn.json_decode(links_json)
  else
    error("couldn't read vault index from file: " .. err)
  end
end

return Cache
