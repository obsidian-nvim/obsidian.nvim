local dates = require "obsidian.agenda.dates"
local source = require "obsidian.agenda.source"
local views = require "obsidian.agenda.views"
local log = require "obsidian.log"

local M = {}

M.parser = require "obsidian.agenda.parser"
M.dates = dates
M.source = source
M.views = views

local request_id = 0
local current_handle

---@param name string|nil
---@return boolean
local function valid_view(name)
  return name == "day" or name == "week" or name == "month" or name == "year" or name == "todo" or name == nil
end

---@param opts { view: string|?, date: integer|?, bufnr: integer|? }|?
---@return integer bufnr
M.open = function(opts)
  opts = opts or {}
  local view_name = opts.view or Obsidian.opts.agenda.default_view or "week"
  if not valid_view(view_name) then
    log.err("Unknown agenda view: " .. tostring(view_name))
    return 0
  end

  local renderer = require "obsidian.agenda.renderers.buffer"
  local state = {
    view_name = view_name,
    base_date = opts.date or os.time(),
    bufnr = opts.bufnr,
  }

  request_id = request_id + 1
  state.request_id = request_id
  local bufnr = renderer.loading(state)
  state.bufnr = bufnr

  if current_handle and type(current_handle) == "table" and type(current_handle.kill) == "function" then
    pcall(current_handle.kill, current_handle, "sigterm")
  end

  local handle = source.collect(function(items, err)
    vim.schedule(function()
      if state.request_id ~= request_id then
        return
      end
      if err then
        renderer.error(bufnr, tostring(err), state)
        return
      end

      local ok, view_or_err = pcall(views.build, view_name, items or {}, state.base_date)
      if not ok then
        renderer.error(bufnr, tostring(view_or_err), state)
        return
      end
      renderer.render(bufnr, view_or_err, state)
    end)
  end)

  current_handle = handle
  state.handle = handle
  return bufnr
end

---@param args string[]
---@return string?, integer?
M.parse_args = function(args)
  local view_name = args[1]
  local date_arg = args[2]

  if view_name and not valid_view(view_name) then
    date_arg = view_name
    view_name = nil
  end

  local date
  if date_arg then
    date = dates.parse(date_arg)
    if not date then
      error("Invalid agenda date: " .. tostring(date_arg))
    end
  end

  return view_name, date
end

---@param arg_lead string
---@return string[]
M.complete = function(arg_lead)
  local choices = { "day", "week", "month", "year", "todo" }
  if arg_lead == "" then
    return choices
  end
  return vim.tbl_filter(function(choice)
    return vim.startswith(choice, arg_lead)
  end, choices)
end

return M
