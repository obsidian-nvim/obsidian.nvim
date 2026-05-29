local api = require "obsidian.api"
local dates = require "obsidian.agenda.dates"
local log = require "obsidian.log"
local Path = require "obsidian.path"

local M = {}

local BUF_NAME = "Obsidian Agenda"
local state_by_buf = {}

---@param item obsidian.agenda.Item
---@return string
local function location(item)
  if not item.path then
    return ""
  end
  local rel = Path.new(item.path):vault_relative_path() or item.path
  if item.lnum then
    return string.format("%s:%d", rel, item.lnum)
  end
  return rel
end

---@param occ obsidian.agenda.Occurrence
---@return string
local function marker(occ)
  if occ.kind == "scheduled" then
    return "S"
  elseif occ.kind == "due" then
    return "D"
  elseif occ.kind == "overdue" then
    return "!"
  elseif occ.kind == "undated" then
    return "?"
  else
    return "-"
  end
end

---@param occ obsidian.agenda.Occurrence
---@return string
local function render_occurrence(occ)
  local item = occ.item
  local pieces = { "  ", marker(occ), " " }
  if item.priority then
    pieces[#pieces + 1] = string.format("[#%s] ", item.priority)
  end
  pieces[#pieces + 1] = item.title or ""

  local loc = location(item)
  if loc ~= "" then
    local left = table.concat(pieces)
    local pad = string.rep(" ", math.max(2, 48 - #left))
    return left .. pad .. loc
  end

  return table.concat(pieces)
end

---@param bufnr integer
---@return table
local function get_state(bufnr)
  return state_by_buf[bufnr] or vim.b[bufnr].obsidian_agenda_state or {}
end

---@param bufnr integer
---@param state table
local function set_state(bufnr, state)
  state_by_buf[bufnr] = state
  vim.b[bufnr].obsidian_agenda_state = state
end

---@param bufnr integer
---@param lines string[]
local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

---@param bufnr integer
---@param lhs string|nil
---@param rhs function
---@param desc string
local function map(bufnr, lhs, rhs, desc)
  if lhs == nil or lhs == "" then
    return
  end
  vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, nowait = true, desc = desc })
end

---@param amount integer
local function shift_period(amount)
  local bufnr = vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  local view = state.view_name or "week"
  local base = state.base_date or os.time()
  if view == "day" then
    base = dates.add_days(base, amount)
  elseif view == "week" then
    base = dates.add_days(base, amount * 7)
  elseif view == "month" then
    local d = os.date("*t", base)
    ---@cast d osdateparam
    d.month = d.month + amount
    d.day, d.hour, d.min, d.sec = 1, 12, 0, 0
    base = os.time(d)
  elseif view == "year" then
    local d = os.date("*t", base)
    ---@cast d osdateparam
    d.year = d.year + amount
    d.month, d.day, d.hour, d.min, d.sec = 1, 1, 12, 0, 0
    base = os.time(d)
  end
  require("obsidian.agenda").open { view = view, date = base, bufnr = bufnr }
end

---@param view string
local function switch_view(view)
  local bufnr = vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  require("obsidian.agenda").open { view = view, date = state.base_date or os.time(), bufnr = bufnr }
end

local function refresh()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  require("obsidian.agenda").open { view = state.view_name, date = state.base_date, bufnr = bufnr }
end

local function today()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  require("obsidian.agenda").open { view = state.view_name, date = os.time(), bufnr = bufnr }
end

local function current_occurrence()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = get_state(bufnr)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_items and state.line_items[row]
end

function M.open_item()
  local occ = current_occurrence()
  if not occ then
    return
  end
  local item = occ.item
  if item.actions and type(item.actions.open) == "function" then
    item.actions.open(item)
  elseif item.path then
    api.open_note { filename = item.path, lnum = item.lnum or 1, col = item.col or 0 }
  end
end

local function toggle_file_item(item)
  if not item.path or not item.lnum then
    return false
  end
  local ok, lines = pcall(vim.fn.readfile, item.path)
  if not ok or not lines[item.lnum] then
    return false
  end
  local line = lines[item.lnum]
  local new_marker = item.status == "done" and " " or "x"
  local changed = false
  line = line:gsub("^(%s*[-*+] %)[.%](.*)$", function(prefix, rest)
    changed = true
    return prefix .. "[" .. new_marker .. "]" .. rest
  end, 1)
  if not changed then
    return false
  end
  lines[item.lnum] = line
  vim.fn.writefile(lines, item.path)
  return true
end

function M.toggle_item()
  local occ = current_occurrence()
  if not occ then
    return
  end
  local item = occ.item
  local ok = false
  if item.actions and type(item.actions.toggle) == "function" then
    ok = item.actions.toggle(item) ~= false
  else
    ok = toggle_file_item(item)
  end
  if ok then
    refresh()
  else
    log.warn "Agenda item is not toggleable"
  end
end

---@param bufnr integer
local function install_mappings(bufnr)
  local mappings = Obsidian.opts.agenda.ui.mappings
  map(bufnr, mappings.open, M.open_item, "open agenda item")
  map(bufnr, mappings.toggle, M.toggle_item, "toggle agenda item")
  map(bufnr, mappings.refresh, refresh, "refresh agenda")
  map(bufnr, mappings.next, function()
    shift_period(1)
  end, "next agenda period")
  map(bufnr, mappings.prev, function()
    shift_period(-1)
  end, "previous agenda period")
  map(bufnr, mappings.today, today, "agenda today")
  map(bufnr, mappings.day, function()
    switch_view "day"
  end, "agenda day")
  map(bufnr, mappings.week, function()
    switch_view "week"
  end, "agenda week")
  map(bufnr, mappings.month, function()
    switch_view "month"
  end, "agenda month")
  map(bufnr, mappings.year, function()
    switch_view "year"
  end, "agenda year")
  map(bufnr, mappings.todo, function()
    switch_view "todo"
  end, "agenda todo")
  map(bufnr, mappings.quit, function()
    vim.cmd "close"
  end, "close agenda")
end

---@param opts table
---@return integer
M.ensure_buffer = function(opts)
  if opts and opts.bufnr and vim.api.nvim_buf_is_valid(opts.bufnr) then
    return opts.bufnr
  end

  for _, existing in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(existing) and vim.api.nvim_buf_get_name(existing):match(vim.pesc(BUF_NAME) .. "$") then
      local open_strategy = Obsidian.opts.agenda.ui.open_strategy or "current"
      if open_strategy == "vsplit" then
        vim.cmd "vsplit"
      elseif open_strategy == "hsplit" then
        vim.cmd "split"
      end
      vim.api.nvim_win_set_buf(0, existing)
      return existing
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, BUF_NAME)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "obsidian-agenda"

  local open_strategy = Obsidian.opts.agenda.ui.open_strategy or "current"
  if open_strategy == "vsplit" then
    vim.cmd "vsplit"
  elseif open_strategy == "hsplit" then
    vim.cmd "split"
  end
  vim.api.nvim_win_set_buf(0, bufnr)
  install_mappings(bufnr)

  return bufnr
end

---@param state table
---@return integer
M.loading = function(state)
  local bufnr = M.ensure_buffer(state)
  set_state(bufnr, state)
  set_lines(bufnr, { "Loading agenda..." })
  return bufnr
end

---@param bufnr integer
---@param view obsidian.agenda.View
---@param state table
M.render = function(bufnr, view, state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local lines = { view.title, "" }
  local line_items = {}

  for _, section in ipairs(view.sections) do
    if #section.items > 0 then
      lines[#lines + 1] = section.title
      for _, occ in ipairs(section.items) do
        lines[#lines + 1] = render_occurrence(occ)
        line_items[#lines] = occ
      end
      lines[#lines + 1] = ""
    end
  end

  if #lines == 2 then
    lines[#lines + 1] = "No agenda items."
  end

  state.view_name = view.name
  state.line_items = line_items
  set_state(bufnr, state)
  set_lines(bufnr, lines)
end

---@param bufnr integer
---@param message string
---@param state table
M.error = function(bufnr, message, state)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  set_state(bufnr, state)
  set_lines(bufnr, { "Agenda error:", "", message })
end

return M
