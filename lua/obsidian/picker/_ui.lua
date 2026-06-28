local M = {}

local api = require "obsidian.api"
local log = require "obsidian.log"
local search = require "obsidian.search"
local Path = require "obsidian.path"
local Picker = require "obsidian.picker"
local ut = require "obsidian.picker.util"

local ns = vim.api.nvim_create_namespace "obsidian_picker_ui"

local current

local max_results = 12

---@param entry obsidian.PickerEntry
---@return string
local function entry_search_text(entry)
  local parts = {}
  for _, key in ipairs { "text", "filename", "user_data" } do
    local value = entry[key]
    if value ~= nil then
      parts[#parts + 1] = tostring(value)
    end
  end
  return table.concat(parts, " ")
end

---@param value string|obsidian.PickerEntry
---@param opts obsidian.PickerPickOpts
---@param idx integer
---@return table
local function make_item(value, opts, idx)
  ---@type obsidian.PickerEntry
  local entry
  local display

  if type(value) == "string" then
    entry = { user_data = value, text = value }
    display = value
  else
    entry = value
    display = opts.format_item and opts.format_item(value) or ut.make_display(value)
  end

  display = tostring(display or "")

  return {
    entry = entry,
    display = display,
    search = display .. " " .. entry_search_text(entry),
    idx = idx,
  }
end

---@param items table[]
local function sort_items(items)
  table.sort(items, function(a, b)
    local ad = string.lower(a.display)
    local bd = string.lower(b.display)
    if ad == bd then
      return a.idx < b.idx
    else
      return ad < bd
    end
  end)
end

---@param picker table
---@return table[]
local function filtered_items(picker)
  local query = picker.query
  if query == nil or query == "" then
    return picker.items
  end

  local ok, matches = pcall(vim.fn.matchfuzzy, picker.items, query, { key = "search" })
  if ok then
    return matches
  end

  local ret = {}
  local q = string.lower(query)
  for _, item in ipairs(picker.items) do
    if string.find(string.lower(item.search), q, 1, true) then
      ret[#ret + 1] = item
    end
  end
  return ret
end

---@param buf integer
local function set_common_buf_opts(buf)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
end

---@param win integer
local function set_common_win_opts(win)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("spell", false, { win = win })
end

---@param picker table
local function restore_focus(picker)
  if picker.origin_win and vim.api.nvim_win_is_valid(picker.origin_win) then
    vim.api.nvim_set_current_win(picker.origin_win)
  end
end

---@param picker table
---@param restore boolean|?
local function close_picker(picker, restore)
  if picker.closed then
    return
  end
  picker.closed = true

  if current == picker then
    current = nil
  end

  for _, win in ipairs { picker.results_win, picker.input_win } do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  for _, buf in ipairs { picker.results_buf, picker.input_buf } do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  if restore then
    restore_focus(picker)
  end
end

local function close_current()
  if current then
    close_picker(current, true)
  end
end

---@param picker table
local function sync_query(picker)
  if not vim.api.nvim_buf_is_valid(picker.input_buf) then
    return
  end
  picker.query = vim.api.nvim_buf_get_lines(picker.input_buf, 0, 1, false)[1] or ""
end

---@param picker table
local function render(picker)
  if picker.closed or not vim.api.nvim_buf_is_valid(picker.results_buf) then
    return
  end

  sync_query(picker)
  picker.matches = filtered_items(picker)

  local limit = math.min(picker.max_results, #picker.matches)
  if picker.selection > limit then
    picker.selection = limit
  end
  if picker.selection < 1 then
    picker.selection = 1
  end

  local lines = {}
  for i = 1, limit do
    lines[#lines + 1] = (i == picker.selection and "❯ " or "  ") .. picker.matches[i].display
  end
  if #lines == 0 then
    lines[1] = "  No results"
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = picker.results_buf })
  vim.api.nvim_buf_set_lines(picker.results_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(picker.results_buf, ns, 0, -1)
  if #picker.matches > 0 then
    vim.api.nvim_buf_set_extmark(picker.results_buf, ns, picker.selection - 1, 0, {
      hl_group = "Visual",
      hl_eol = true,
    })
  else
    vim.api.nvim_buf_set_extmark(picker.results_buf, ns, 0, 0, {
      hl_group = "Comment",
      hl_eol = true,
    })
  end
  vim.api.nvim_set_option_value("modifiable", false, { buf = picker.results_buf })

  if vim.api.nvim_win_is_valid(picker.results_win) then
    vim.api.nvim_win_set_config(picker.results_win, { height = #lines })
  end
end

---@param delta integer
local function move_selection(delta)
  if not current or current.closed then
    return
  end
  local limit = math.min(current.max_results, #current.matches)
  if limit == 0 then
    return
  end

  current.selection = current.selection + delta
  if current.selection < 1 then
    current.selection = limit
  elseif current.selection > limit then
    current.selection = 1
  end

  render(current)
end

---@param picker table
---@return obsidian.PickerEntry|?
local function selected_entry(picker)
  if not picker.matches or #picker.matches == 0 then
    return nil
  end
  local item = picker.matches[picker.selection]
  return item and item.entry or nil
end

---@param picker table
---@param callback function
---@param ... any
local function close_and_call(picker, callback, ...)
  local args = { ... }
  close_picker(picker, true)
  callback(unpack(args))
end

local function confirm_current()
  local picker = current
  if not picker or picker.closed then
    return
  end

  local entry = selected_entry(picker)
  if not entry then
    return
  end

  local arg = entry
  if picker.default_callback and entry.filename == nil and entry.user_data ~= nil then
    arg = entry.user_data
  end

  close_and_call(picker, picker.callback, arg)
end

---@param mapping obsidian.PickerMappingOpts
local function run_query_mapping(mapping)
  local picker = current
  if not picker or picker.closed then
    return
  end

  sync_query(picker)
  if picker.query == nil or vim.trim(picker.query) == "" then
    return
  end

  if mapping.keep_open then
    mapping.callback(picker.query)
  else
    close_and_call(picker, mapping.callback, picker.query)
  end
end

---@param mapping obsidian.PickerMappingOpts
local function run_selection_mapping(mapping)
  local picker = current
  if not picker or picker.closed then
    return
  end

  local entry = selected_entry(picker)
  if entry then
    if mapping.keep_open then
      mapping.callback(entry)
    else
      close_and_call(picker, mapping.callback, entry)
    end
    return
  end

  if mapping.fallback_to_query then
    sync_query(picker)
    if picker.query and vim.trim(picker.query) ~= "" then
      if mapping.keep_open then
        mapping.callback(picker.query)
      else
        close_and_call(picker, mapping.callback, picker.query)
      end
    end
  end
end

---@param buf integer
---@param lhs string|?
---@param rhs function
local function map(buf, lhs, rhs)
  if lhs == nil or lhs == "" then
    return
  end
  vim.keymap.set({ "i", "n" }, lhs, rhs, { buffer = buf, nowait = true, silent = true })
end

---@param picker table
local function set_mappings(picker)
  for _, buf in ipairs { picker.input_buf, picker.results_buf } do
    map(buf, "<CR>", confirm_current)
    map(buf, "<Esc>", close_current)
    map(buf, "<C-c>", close_current)
    map(buf, "<Down>", function()
      move_selection(1)
    end)
    map(buf, "<C-n>", function()
      move_selection(1)
    end)
    map(buf, "<Tab>", function()
      move_selection(1)
    end)
    map(buf, "<Up>", function()
      move_selection(-1)
    end)
    map(buf, "<C-p>", function()
      move_selection(-1)
    end)
    map(buf, "<S-Tab>", function()
      move_selection(-1)
    end)
    vim.keymap.set("n", "q", close_current, { buffer = buf, nowait = true, silent = true })

    for key, mapping in pairs(picker.query_mappings or {}) do
      map(buf, key, function()
        run_query_mapping(mapping)
      end)
    end

    for key, mapping in pairs(picker.selection_mappings or {}) do
      map(buf, key, function()
        run_selection_mapping(mapping)
      end)
    end
  end
end

---@param prompt_title string|?
---@return integer, integer, integer, integer
local function layout(prompt_title)
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local max_width = math.max(20, columns - 4)
  local width = math.min(max_width, math.max(40, math.floor(columns * 0.6)))
  local row = math.max(1, math.floor(lines * 0.18))
  local col = math.max(0, math.floor((columns - width) / 2))
  local available = math.max(1, lines - row - 6)
  local height = math.min(max_results, available)

  if prompt_title and vim.fn.strdisplaywidth(prompt_title) + 4 > width then
    width = math.min(max_width, vim.fn.strdisplaywidth(prompt_title) + 4)
    col = math.max(0, math.floor((columns - width) / 2))
  end

  return row, col, width, height
end

---@param values string[]|obsidian.PickerEntry[]
---@param opts obsidian.PickerPickOpts|? Options.
M.pick = function(values, opts)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  if vim.tbl_isempty(values) then
    return log.info "No results"
  end

  if current then
    close_picker(current, false)
  end

  local origin_win = vim.api.nvim_get_current_win()
  local input_buf = vim.api.nvim_create_buf(false, true)
  local results_buf = vim.api.nvim_create_buf(false, true)
  set_common_buf_opts(input_buf)
  set_common_buf_opts(results_buf)

  local row, col, width, height = layout(opts.prompt_title)
  local title = opts.prompt_title or "Quick Switch"

  local input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " " .. title .. " ",
    title_pos = "left",
  })

  local results_win = vim.api.nvim_open_win(results_buf, false, {
    relative = "editor",
    row = row + 3,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
  })

  set_common_win_opts(input_win)
  set_common_win_opts(results_win)

  vim.api.nvim_set_option_value("cursorline", false, { win = input_win })
  vim.api.nvim_set_option_value("cursorline", false, { win = results_win })

  local items = {}
  for idx, value in ipairs(values) do
    items[#items + 1] = make_item(value, opts, idx)
  end
  sort_items(items)

  local default_callback = opts.callback == nil
  local picker = {
    input_buf = input_buf,
    input_win = input_win,
    results_buf = results_buf,
    results_win = results_win,
    origin_win = origin_win,
    callback = opts.callback or api.open_note,
    default_callback = default_callback,
    query_mappings = opts.query_mappings,
    selection_mappings = opts.selection_mappings,
    items = items,
    matches = {},
    selection = 1,
    query = opts.query or "",
    max_results = height,
  }

  current = picker

  if opts.query and opts.query ~= "" then
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { opts.query })
  else
    vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { "" })
  end

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = input_buf,
    callback = function()
      vim.schedule(function()
        if current == picker and not picker.closed then
          picker.selection = 1
          render(picker)
        end
      end)
    end,
  })

  set_mappings(picker)
  render(picker)

  vim.schedule(function()
    if not picker.closed and vim.api.nvim_win_is_valid(input_win) then
      vim.api.nvim_set_current_win(input_win)
      local query = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
      vim.api.nvim_win_set_cursor(input_win, { 1, #query })
      vim.cmd "startinsert!"
    end
  end)
end

--- Find files in a directory.
---
---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  opts = opts or {}

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local paths = {}

  search.find_async(
    dir,
    nil,
    { include_non_markdown = opts.include_non_markdown },
    function(path)
      paths[#paths + 1] = path
    end,
    vim.schedule_wrap(function()
      if vim.tbl_isempty(paths) then
        return log.info "Search result empty"
      elseif #paths == 1 and opts.query and vim.trim(opts.query) ~= "" then
        if opts.callback then
          return opts.callback(paths[1])
        else
          return api.open_note { filename = paths[1] }
        end
      end

      ---@type obsidian.PickerEntry[]
      local items = {}
      for _, path in ipairs(paths) do
        items[#items + 1] = {
          filename = path,
          lnum = 1,
          col = 0,
          text = ut.make_display {
            filename = path,
          },
        }
      end

      M.pick(items, {
        prompt_title = opts.prompt_title,
        query = opts.query,
        query_mappings = opts.query_mappings,
        selection_mappings = opts.selection_mappings,
        format_item = function(item)
          return item.text or item.filename or ""
        end,
        callback = function(item)
          if opts.callback then
            opts.callback(item.filename)
          else
            api.open_note(item)
          end
        end,
      })
    end)
  )
end

-- Grep is intentionally the native implementation for now.
M.grep = require("obsidian.picker._default").grep

return M
