local async = require "plenary.async"
local abc = require "obsidian.abc"
local Note = require "obsidian.note"
local log = require "obsidian.log"
local EventTypes = require("obsidian.filewatch").EventTypes
local uv = vim.uv
local api = require "obsidian.api"

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
---@field aliases string[] The alises of the note founded in the frontmatter.
---@field last_updated number The last time the note was updated in seconds since epoch.
---@field tags string[] The tags of the note.

---Converts the cache to JSON and saves to the file at the given path.
---@param cache_notes { [string]: obsidian.cache.CacheNote } Dictionary where key is the relative path and value is the cache of the note.
---@param cache_file_path string Location to save the cache
local save_cache_notes_to_file = function(cache_notes, cache_file_path)
  local file, err = io.open(cache_file_path, "w")

  if file then
    file:write(vim.json.encode(cache_notes))
    file:close()
  else
    error(table.concat { "Couldn't write vault index to the file: ", cache_file_path, ". Description: ", err })
  end
end

---Update the cache file for changed files.
---@param self obsidian.Cache
---@return fun (changed_files: obsidian.filewatch.CallbackArgs[])
local create_on_file_change_callback = function(self)
  return function(changed_files)
    vim.schedule(function()
      local cache_notes = self:get_cache_notes_from_file()

      if not cache_notes then
        return
      end

      local update_cache_file = function()
        vim.schedule(function()
          save_cache_notes_to_file(cache_notes, self:get_cache_path())
        end)
      end

      local left = #changed_files

      for _, file in ipairs(changed_files) do
        local relative_path = file.absolute_path:gsub(self.client.dir.filename .. "/", "")

        ---@param note obsidian.Note|?
        local update_cache_dictionary = function(note)
          if note then
            ---@type obsidian.cache.CacheNote
            local founded_cache = {
              absolute_path = file.absolute_path,
              aliases = note.aliases,
              last_updated = file.stat.mtime.sec,
              tags = note.tags,
            }

            cache_notes[relative_path] = founded_cache
          end

          left = left - 1

          if left == 0 then
            update_cache_file()
          end
        end

        if file.event == EventTypes.deleted and cache_notes[relative_path] then
          cache_notes[relative_path] = nil
          update_cache_dictionary()
        else
          async.run(function()
            return Note.from_file_async(file.absolute_path, { read_only_frontmatter = true })
          end, update_cache_dictionary)
        end
      end
    end)
  end
end

---Checks for note cache that were updated outside the vault.
---@param self obsidian.Cache
local check_cache_notes_are_fresh = function(self)
  local founded_notes = api.get_all_notes_from_vault(self.client:vault_root().filename)
  local cache_notes = self:get_cache_notes_from_file()

  if not cache_notes or not founded_notes then
    return
  end

  ---@type { [string]: obsidian.cache.CacheNote }
  local updated = {}
  local completed = 0
  local total = #founded_notes
  local on_done = function()
    completed = completed + 1

    if completed == total then
      vim.schedule(function()
        save_cache_notes_to_file(updated, self:get_cache_path())
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
      local tags
      if cache_note and cache_note.last_updated == stat.mtime.sec then
        aliases = cache_note.aliases
        tags = cache_note.tags
      else
        local note = Note.from_file(founded_note, { read_only_frontmatter = true })
        aliases = note.aliases
        tags = note.tags
      end

      ---@type obsidian.cache.CacheNote
      local updated_cache = {
        absolute_path = founded_note,
        last_updated = stat.mtime.sec,
        aliases = aliases,
        tags = tags,
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
    callback(err == nil)
  end)
end

---Watches the vault for changes.
---@param self obsidian.Cache
local enable_filewatch = function(self)
  local filewatch = require "obsidian.filewatch"
  filewatch.watch(self.client.dir.filename, create_on_file_change_callback(self))

  vim.api.nvim_create_autocmd({ "QuitPre", "ExitPre" }, {
    callback = function()
      filewatch.release_resources()
    end,
  })
end

---@param self obsidian.Cache
local check_vault_cache = function(self)
  check_file_exists(self:get_cache_path(), function(exists)
    if exists then
      vim.schedule(function()
        check_cache_notes_are_fresh(self)
      end)
    else
      vim.schedule(function()
        self:rebuild_cache()
      end)
    end
  end)
end

---@param client obsidian.Client
Cache.new = function(client)
  local self = Cache.init()
  self.client = client

  if client.opts.cache.enabled then
    enable_filewatch(self)

    check_vault_cache(self)
  end

  return self
end

--- Reads all notes in the vaults and returns the founded data.
---@param client obsidian.Client
---@param callback fun (note_caches: { [string]: obsidian.cache.CacheNote })
local get_cache_notes_from_vault = function(client, callback)
  ---@type { [string]: obsidian.cache.CacheNote }
  local created_note_caches = {}

  local founded_notes = api.get_all_notes_from_vault(client.dir.filename)

  assert(founded_notes)

  local notes_parsed = 0

  local on_exit = function()
    callback(created_note_caches)
  end

  local on_note_parsed = function(note)
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
      last_updated = last_updated,
      tags = note.tags or {},
    }

    created_note_caches[relative_path] = note_cache

    notes_parsed = notes_parsed + 1

    if notes_parsed == #founded_notes then
      on_exit()
    end
  end

  for _, note_path in ipairs(founded_notes) do
    async.run(function()
      return Note.from_file_async(note_path, { read_only_frontmatter = true })
    end, on_note_parsed)
  end
end

--- Reads all notes in the vaults and saves them to the cache file.
---@param self obsidian.Cache
Cache.rebuild_cache = function(self)
  if not self.client.opts.cache.enabled then
    log.error "The cache is disabled. Cannot rebuild cache."
    return
  end

  log.info "Rebuilding cache..."

  get_cache_notes_from_vault(self.client, function(founded_links)
    save_cache_notes_to_file(founded_links, self:get_cache_path())
    log.info "The cache was rebuild."
  end)
end

---Reads the cache file from client.opts.cache.path and returns the loaded cache.
---@param self obsidian.Cache
---@return { [string]: obsidian.cache.CacheNote }|? Key is the relative path to the vault, value is the cache of the note.
Cache.get_cache_notes_from_file = function(self)
  local file, err = io.open(self:get_cache_path(), "r")

  if file then
    local links_json = file:read()
    file:close()
    return vim.json.decode(links_json)
  elseif err then
    log.err(err)
  end

  return nil
end

---Reads the cache file from client.opts.cache.path and returns founded note cache without key.
---@param self obsidian.Cache
---@return obsidian.cache.CacheNote[]
Cache.get_cache_notes_without_key = function(self)
  local cache_with_index = self:get_cache_notes_from_file()
  assert(cache_with_index)
  return vim.tbl_values(cache_with_index)
end

Cache.get_cache_path = function(self)
  local normalized_path = vim.fs.normalize(self.client.opts.cache.path)
  return vim.fs.joinpath(self.client.dir.filename, normalized_path)
end

return Cache
