local uv = vim.loop
local util = require "obsidian.util"
local api = require "obsidian.api"

local M = {}

---@enum obsidian.filewatch.EventType
M.EventTypes = {
  unknown = 0,
  changed = 1,
  renamed = 2,
  deleted = 3,
}

---@class obsidian.filewatch.CallbackArgs
---@field absolute_path string The absolute path to the changed file.
---@field event obsidian.filewatch.EventType The type of the event.
---@field stat uv.fs_stat.result|? The uv file info.

---Creates default callback if error occured in fs_event_start.
---@param path string The filepath where error occured.
---@return fun(error: string) Default function which accepts an error.
local make_default_error_cb = function(path)
  return function(error)
    error(table.concat { "obsidian.watch(", path, ")", "encountered an error: ", error })
  end
end

--- Minimal time in milliseconds to allow the event to fire for a single file.
local MIN_INTERVAL = 50
--- The time in milleseconds when the changed files will be send to the client.
local CALLBACK_AFTER_INTERVAL = 500

---@type obsidian.filewatch.CallbackArgs[]
local queue_to_send = {}
---@type uv.uv_timer_t
local queue_timer
---@type uv.uv_fs_event_t[]
local watch_handlers = {}

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
---@param on_event fun (changed_files: obsidian.filewatch.CallbackArgs[])
---@param on_error fun (err: string)
---@param opts {recursive: boolean}
---@return uv.uv_fs_event_t
local function watch_path(path, on_event, on_error, opts)
  local handle = uv.new_fs_event()

  if not handle then
    error "couldn't create event handler"
  end

  local flags = {
    watch_entry = false, -- true = if you pass dir, watch the dir inode only, not the dir content
    stat = false, -- true = don't use inotify/kqueue but periodic check, not implemented
    recursive = opts.recursive, -- true = watch dirs inside dirs. For now only works on Windows and MacOS
  }

  ---@type {[string]: number|?}
  local last_received_files = {}

  ---Tracks the changed files and returns them to the client after some time.
  ---@param send_arg obsidian.filewatch.CallbackArgs
  local add_to_queue = function(send_arg)
    table.insert(queue_to_send, send_arg)

    queue_timer:stop()

    queue_timer:start(CALLBACK_AFTER_INTERVAL, 0, function()
      on_event(queue_to_send)
      queue_to_send = {}
    end)
  end

  local event_cb = function(err, filename, events)
    if err then
      on_error(err)
      return
    end

    if not can_fire_callback(filename, last_received_files) then
      return
    end

    local folder_path = uv.fs_event_getpath(handle)

    local full_path = table.concat { folder_path, filename }

    uv.fs_stat(full_path, function(stat_err, stat)
      if stat_err then
        on_event {
          absolute_path = full_path,
          event = M.EventTypes.deleted,
          stat = nil,
        }
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

      add_to_queue {
        absolute_path = full_path,
        event = event_type,
        stat = stat,
      }
    end)
  end

  local success, err, err_name = uv.fs_event_start(handle, path, flags, event_cb)

  if not success then
    error("couldn't create fs event! error - " .. err .. " err_name: " .. err_name)
  end

  return handle
end

---Create a watch handler (several if on Linux) which calls the callback function when a file is changed.
---Calls the callback function only after CALLBACK_AFTER_INTERVAL.
---If an error occured, called on_error function.
---TODO if a new folder will be created, it won't be tracked.
---@param path string The path to the watch folder.
---@param callback fun (changed_files: obsidian.filewatch.CallbackArgs[])
---@param on_error fun (err: string)|?
M.watch = function(path, callback, on_error)
  if not path or path == "" then
    error "Path cannot be empty."
  end

  assert(callback)

  if on_error == nil then
    on_error = make_default_error_cb(path)
  end

  local new_timer = uv.new_timer()

  assert(new_timer)

  queue_timer = new_timer

  local sysname = util.get_os()

  -- uv doesn't support recursive flag on Linux
  if sysname == util.OSType.Linux then
    table.insert(watch_handlers, watch_path(path, callback, on_error, { recursive = false }))

    local subfolders = api.get_sub_dirs_from_vault(path)

    assert(subfolders)

    for _, dir in ipairs(subfolders) do
      table.insert(watch_handlers, watch_path(dir, callback, on_error, { recursive = false }))
    end
  else
    watch_handlers = { watch_path(path, callback, on_error, { recursive = true }) }
  end
end

M.release_resources = function()
  for _, handle in ipairs(watch_handlers) do
    if handle then
      handle:stop()
      if not handle.is_closing then
        handle:close()
      end
    end
  end

  queue_timer:stop()
  if not queue_timer.is_closing then
    queue_timer:close()
  end
end

return M
