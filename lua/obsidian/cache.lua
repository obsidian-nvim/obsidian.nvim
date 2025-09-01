local async = require "plenary.async"
local Note = require "obsidian.note"
local log = require "obsidian.log"
local EventTypes = require("obsidian.filewatch").EventTypes
local uv = vim.uv
local api = require "obsidian.api"

---This table allows you to find the notes in your vault more quickly.
---It scans your vault and saves the founded metadata to the file specified in your CacheOpts (by default it's ".cache.json").
---For now, this allows to search for alises of your
---notes in much shorter time.
local M = {}

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

local get_cache_path = function()
  local workspace_path = Obsidian.dir.filename
  local opts = Obsidian.opts
  local normalized_path = vim.fs.normalize(opts.cache.path)
  return vim.fs.joinpath(workspace_path, normalized_path)
end

---@param cache_notes { [string]: obsidian.cache.CacheNote } Dictionary where key is the relative path and value is the cache of the note.
local update_cache = function(cache_notes)
  Obsidian.cache = cache_notes
  save_cache_notes_to_file(cache_notes, get_cache_path())
end

---Creates a funciton, which updates the cache file when notes in workspace are changed.
---@return fun (changed_files: obsidian.filewatch.CallbackArgs[])
local create_on_file_change_callback = function()
  return function(changed_files)
    local workspace_path = Obsidian.dir.filename

    vim.schedule(function()
      local cache_notes = Obsidian.cache

      if not cache_notes then
        return
      end

      local update_cache_file = function()
        vim.schedule(function()
          update_cache(cache_notes)
        end)
      end

      local left = #changed_files

      for _, file in ipairs(changed_files) do
        local relative_path = file.absolute_path:gsub(workspace_path .. "/", "")

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

---Reads the cache file from client.opts.cache.path and returns the loaded cache.
---@return { [string]: obsidian.cache.CacheNote }|? Key is the relative path to the vault, value is the cache of the note.
local get_cache_notes_from_file = function()
  local file, err = io.open(get_cache_path(), "r")

  if file then
    local links_json = file:read()
    file:close()
    return vim.json.decode(links_json)
  elseif err then
    log.err(err)
  end

  return nil
end

---Checks for note cache that were updated outside the vault.
local check_cache_notes_are_fresh = function()
  local workspace_path = Obsidian.dir.filename

  local founded_notes = api.get_all_notes_from_vault(workspace_path)
  local old_cache_notes = get_cache_notes_from_file()

  if not old_cache_notes or not founded_notes then
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
        update_cache(updated)
      end)
    end
  end

  for _, founded_note in ipairs(founded_notes) do
    local relative_path = founded_note:gsub(workspace_path .. "/", "")

    uv.fs_stat(founded_note, function(err, stat)
      if err then
        -- If the err is occured, the file is deleted, so we don't need to add it to the list.
        on_done()
        return
      end

      local cache_note = old_cache_notes[relative_path]

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
local enable_filewatch = function()
  local workspace_path = Obsidian.dir.filename

  -- We need a lock file to check if a neovim instance is open in the workspace.
  -- This prevents creating more filewatches in the same workspace which can lead to bugs and can decrease performaance.
  local lock_name = table.concat { Obsidian.dir.stem, ".lock" }
  local lock_file_path = vim.fs.joinpath(vim.fn.stdpath "state", lock_name)

  if uv.fs_stat(lock_file_path) then
    local lock_file = io.open(lock_file_path, "r")

    assert(lock_file)

    local pid = lock_file:read()
    lock_file:close()

    if api.check_pid_exists(pid) then
      return
    end
  end

  local lock_file_handler = io.open(lock_file_path, "w")

  assert(lock_file_handler)

  local current_nvim_pid = uv.os_getpid()
  lock_file_handler:write(current_nvim_pid)
  lock_file_handler:close()

  local filewatch = require "obsidian.filewatch"
  filewatch.watch(workspace_path, create_on_file_change_callback())

  vim.api.nvim_create_autocmd({ "QuitPre", "ExitPre" }, {
    callback = function()
      filewatch.release_resources()
      os.remove(lock_file_path)
    end,
  })
end

local check_vault_cache = function()
  check_file_exists(get_cache_path(), function(exists)
    if exists then
      vim.schedule(function()
        check_cache_notes_are_fresh()
      end)
    else
      vim.schedule(function()
        M.rebuild_cache()
      end)
    end
  end)
end

--- Reads all notes in the vaults and returns the founded data.
---@param callback fun (note_caches: { [string]: obsidian.cache.CacheNote })
local get_cache_notes_from_vault = function(callback)
  local workspace_path = Obsidian.dir.filename

  ---@type { [string]: obsidian.cache.CacheNote }
  local created_note_caches = {}

  local founded_notes = api.get_all_notes_from_vault(workspace_path)

  assert(founded_notes)

  local notes_parsed = 0

  local on_exit = function()
    callback(created_note_caches)
  end

  local on_note_parsed = function(note)
    local absolute_path = note.path.filename
    local relative_path = absolute_path:gsub(workspace_path .. "/", "")

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
M.rebuild_cache = function()
  if not Obsidian.opts.cache.enabled then
    log.error "The cache is disabled. Cannot rebuild cache."
    return
  end

  log.info "Rebuilding cache..."

  get_cache_notes_from_vault(function(cache_notes)
    update_cache(cache_notes)
    log.info "The cache was rebuild."
  end)
end

M.activate_cache = function()
  enable_filewatch()

  check_vault_cache()
end

return M
