local uv = vim.loop
local util = require "obsidian.util"
local log = require("obsidian.log")

local M = {}

---@class obsidian.filewatch.FileWatchOpts

---Creates default callback if error occured in fs_event_start.
---@param path string The filepath where error occured.
---@return fun(error: string) Default function which accepts an error.
local make_default_error_cb = function(path)
  return function(error)
    error(table.concat { "obsidian.watch(", path, ")", "encountered an error: ", error })
  end
end

---@enum obsidian.filewatch.EventType
M.EventTypes = {
  unknown = 0,
  changed = 1,
  renamed = 2,
  deleted = 3,
}

--- Minimal time in milliseconds to allow the event to fire.
local MIN_INTERVAL = 50

---Check if the event is not a duplicate or the received name is not `~` or a number.
---@param filename string
---@param last_received_files {[string]: number|?}
---@return boolean
local can_fire_callback = function(filename, last_received_files)
  local now = uv.now()

  local last_callback_time = last_received_files[filename]

  if last_callback_time then
    if now - last_callback_time < MIN_INTERVAL then
      return false
    end
  end

  last_received_files[filename] = now

  if filename:sub(#filename - 2, #filename) ~= ".md" then
    return false
  end

  return true
end

--- Watch path and calls on_event(filename, event_type) or on_error(error)
---@param path string
---@param on_event fun (absolute_path: string, event_type: obsidian.filewatch.EventType, stat: uv.fs_stat.result|?)
---@param on_error fun (err: string)
---@param opts {recursive: boolean}
---@return uv.uv_fs_event_t
local function watch_path(path, on_event, on_error, opts)
  local handle = uv.new_fs_event()

  if not handle then
    error "couldn't create event handler"
  end

  local flags = {
    watch_entry = false,        -- true = if you pass dir, watch the dir inode only, not the dir content
    stat = false,               -- true = don't use inotify/kqueue but periodic check, not implemented
    recursive = opts.recursive, -- true = watch dirs inside dirs. For now only works on Windows and MacOS
  }

  local last_received_files = {}

  local event_cb = function(err, filename, events)
    if err then
      on_error(err)
      return
    end

    if not can_fire_callback(filename, last_received_files) then
      return
    end

    local folder_path = uv.fs_event_getpath(handle)

    local full_path = table.concat { folder_path, "/", filename }

    uv.fs_stat(full_path, function(stat_err, stat)
      if stat_err then
        on_event(full_path, M.EventTypes.deleted, nil)
        return
      end

      local event_type
      if events.change then
        event_type = M.EventTypes.changed
      elseif events.rename then
        event_type = M.EventTypes.renamed
      else
        event_type = M.EventTypes.unknown
      end

      log.warn(table.concat({ "File (", filename, ") was updated at " .. os.date("%H:%M:%S") }))

      on_event(full_path, event_type, stat)
    end)
  end

  local success, err, err_name = uv.fs_event_start(handle, path, flags, event_cb)

  if not success then
    error("couldn't create fs event! error - " .. err .. " err_name: " .. err_name)
  end

  return handle
end

---Create a watch handler which uses callback function when a file is changed.
---If an error occured, called on_error function.
---TODO if a new folder will be created, it won't be tracked
---@param path string
---@param callback fun (absolute_path: string, event_type: obsidian.filewatch.EventType, stat: uv.fs_stat.result|?)
---@param on_error fun (err: string)|?
---@return uv.uv_fs_event_t[]
M.watch = function(path, callback, on_error)
  if not path or path == "" then
    error "Path cannot be empty."
  end

  if not callback then
    error "Callback cannot be empty!"
  end

  if on_error == nil then
    on_error = make_default_error_cb(path)
  end

  local sysname = util.get_os()

  if sysname == util.OSType.Linux then
    local handle = io.popen("fd -t directory -a --base-directory " .. path)
    if not handle then
      error "Failed to execute command"
    end

    local subdirs_handlers = {}

    for dir in handle:lines() do
      table.insert(subdirs_handlers, watch_path(dir, callback, on_error, { recursive = false }))
    end

    handle:close()

    return subdirs_handlers
  else
    return { watch_path(path, callback, on_error, { recursive = true }) }
  end
end

return M
