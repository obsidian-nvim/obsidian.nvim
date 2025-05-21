local async = require "plenary.async"
local abc = require "obsidian.abc"
local search = require "obsidian.search"
local Note = require "obsidian.note"
local log = require "obsidian.log"
local EventTypes = require("obsidian.filewatch").EventTypes
local uv = vim.uv

---This class allows you to find the notes in your vault more quickly.
---It scans your vault and saves the founded metadata to the file specified in your CacheOpts (by default it's ".cache.json").
---For now, this allows to search for alises of your
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

---Converts the cache to JSON and saves to the file at the given path.
---@param cache_notes { [string]: obsidian.cache.CacheNote } Dictionary where key is the relative path and value is the cache of the note.
---@param cache_file_path string|obsidian.Note Location to save the cache
local save_cache_notes_to_file = function(cache_notes, cache_file_path)
  local save_path

  if type(cache_file_path) == "obsidian.Note" then
    save_path = cache_file_path.path.filename
  else
    save_path = cache_file_path
  end

  local file, err = io.open(save_path, "w")

  if file then
    file:write(vim.fn.json_encode(cache_notes))
    file:close()
  else
    error(table.concat { "Couldn't write vault index to the file: ", save_path, ". Description: ", err })
  end
end

---TODO: there can be a possibility, that multiple files will be changed at the same time, which will trigger multiple
---change events, which can lead to performance issues and data loss. In order to avoid this the filewatcher should return multiple files only after
---some time.
---@param self obsidian.Cache
---@return fun (absolute_path: string, event_type: obsidian.filewatch.EventType, stat: uv.fs_stat.result)
local create_on_file_change_callback = function(self)
  return function(absolute_path, event_type, stat)
    vim.schedule(function()
      local ok, cache_notes = pcall(self.get_cache_notes_from_file, self)

      if not ok then
        log.err("An error occured when reading from the cache file.")
        return
      end

      local relative_path = absolute_path:gsub(self.client.dir.filename .. "/", "")

      ---update the vault when the note is returned
      ---@param note obsidian.Note|?
      local refresh_vault = function(note)
        if note then
          local founded_cache = {
            absolute_path = absolute_path,
            aliases = note.aliases,
            relative_path = relative_path,
            last_updated = stat.mtime.sec,
          }

          cache_notes[relative_path] = founded_cache
        end

        vim.schedule(function()
          save_cache_notes_to_file(cache_notes, self.client.opts.cache.cache_path)
        end)
      end

      if event_type == EventTypes.deleted and cache_notes[relative_path] then
        cache_notes[relative_path] = nil
        refresh_vault()
      else
        async.run(function()
          return Note.from_file_async(absolute_path, { read_only_frontmatter = true })
        end, refresh_vault)
      end
    end)
  end
end

---Gets the notes from the vault recursivly
---@param path string Path to a subfolder of the vault.
---@param files string[]|? Founded pathes to notes.
---@return string[]
local function list_notes_recursive(path, files)
  files = files or {}
  local req = uv.fs_scandir(path)
  if not req then return files end

  while true do
    local name, type = uv.fs_scandir_next(req)
    if not name then break end
    if name ~= "." and name ~= ".." then
      local full_path = path .. "/" .. name
      if type == "directory" then
        list_notes_recursive(full_path, files)
      elseif type == "file" and full_path:sub(#full_path - 2, #full_path) == ".md" then
        table.insert(files, full_path)
      end
    end
  end

  return files
end

---Gets all notes from the vault.
---@param path string The path to the vault.
---@return string[] The path to the notes.
local function get_all_notes_from_vault(path)
  return list_notes_recursive(path)
end

---Checks for note cache that were updated outside the vault.
---@param self obsidian.Cache
local check_cache_notes_are_fresh = function(self)
  local founded_notes = get_all_notes_from_vault(self.client:vault_root().filename)
  local cache_notes = self.get_cache_notes_from_file(self)

  ---@type { [string]: obsidian.cache.CacheNote }
  local updated = {}
  local completed = 0
  local total = #founded_notes
  local on_done = function()
    completed = completed + 1

    if completed == total then
      vim.schedule(function()
        save_cache_notes_to_file(updated, self.client.opts.cache.cache_path)
      end)
    end
  end

  for _, founded_note in ipairs(founded_notes) do
    local relative_path = founded_note:gsub(self.client.dir.filename .. "/", "")

    uv.fs_stat(founded_note, function(err, stat)
      if err then
        -- If the err is occured, the file is deleted, so we don't need to add it to the list.
        on_done()
        return
      end

      local cache_note = cache_notes[relative_path]

      local aliases
      if cache_note and cache_note.last_updated == stat.mtime.sec then
        aliases = cache_note.aliases
      else
        local note = Note.from_file(founded_note, { read_only_frontmatter = true })
        aliases = note.aliases
      end

      ---@type obsidian.cache.CacheNote
      local updated_cache = {
        absolute_path = founded_note,
        last_updated = stat.mtime.sec,
        aliases = aliases,
        relative_path = relative_path,
      }

      updated[relative_path] = updated_cache

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
---@return { [string]: obsidian.cache.CacheNote }
local get_cache_notes_from_vault = function(client)
  local interator = search.find(client.dir, "", nil)

  ---@type { [string]: obsidian.cache.CacheNote }
  local created_note_caches = {}

  local notepath = interator()

  --TODO add indexing progress
  while notepath do
    --TODO make async
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

    created_note_caches[relative_path] = note_cache

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

---Reads the cache file from client.opts.cache.cache_path and returns the loaded cache.
---@param self obsidian.Cache
---@return { [string]: obsidian.cache.CacheNote } Key is the relative path to the vault, value is the cache of the note.
Cache.get_cache_notes_from_file = function(self)
  local file, err = io.open(self.client.opts.cache.cache_path, "r")

  if file then
    local links_json = file:read()
    file:close()
    return vim.fn.json_decode(links_json)
  else
    print(err)
  end
end

---Reads the cache file from client.opts.cache.cache_path and returns founded note cache without key.
---@param self obsidian.Cache
---@return obsidian.cache.CacheNote[]
Cache.get_cache_notes_without_key = function(self)
  local cache_with_index = self:get_cache_notes_from_file()

  local cache_without_index = {}
  for _, value in pairs(cache_with_index) do
    table.insert(cache_without_index, value)
  end

  return cache_without_index
end

return Cache
