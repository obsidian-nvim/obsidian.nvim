local picker_util = require "obsidian.picker.util"

local M = {}

local highlight_ns = vim.api.nvim_create_namespace "obsidian_picker_ui"
local default_max_results = 12
local current

---@class obsidian.picker.ui.Item
---@field value   any
---@field display string
---@field search  string

---@class obsidian.picker.ui.Layout
---@field row            integer
---@field col            integer
---@field width          integer
---@field body_height    integer
---@field preview_height integer | nil

---@class obsidian.picker.ui.Opts
---@field prompt         string | nil
---@field query          string | nil
---@field max_results    integer | nil
---@field format_item    (fun(value: any): string) | nil
---@field preview_item   (fun(value: any): obsidian.ui_select_preview_spec | nil) | nil
---@field query_mappings obsidian.PickerMappingTable | nil

---@class obsidian.picker.ui.Picker
---@field input_buf      integer
---@field input_win      integer
---@field results_buf    integer
---@field results_win    integer
---@field preview_buf    integer | nil                 Owned placeholder buffer.
---@field preview_win    integer | nil
---@field origin_win     integer
---@field opts           obsidian.picker.ui.Opts
---@field on_choice      fun(choices: any[])
---@field items          obsidian.picker.ui.Item[]
---@field matches        obsidian.picker.ui.Item[]
---@field selection      integer
---@field max_results    integer
---@field query          string
---@field closed         boolean
---@field resize_autocmd integer | nil
---@field previewed_item obsidian.picker.ui.Item | nil
local PickerUi = {}
PickerUi.__index = PickerUi

---@param buf    integer
---@param hidden "hide" | "wipe"
local function set_scratch_buf_opts(buf, hidden)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", hidden, { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
end

---@param win integer
local function set_float_win_opts(win)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("spell", false, { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
end

-- ---@param value any
-- ---@return string
-- local function value_search_text(value)
--   if type(value) ~= "table" then
--     return tostring(value)
--   end
--
--   local parts = {}
--   for _, key in ipairs { "text", "filename", "user_data" } do
--     if value[key] ~= nil then
--       parts[#parts + 1] = tostring(value[key])
--     end
--   end
--   return table.concat(parts, " ")
-- end

---@param value any
---@param opts  obsidian.picker.ui.Opts
---@return obsidian.picker.ui.Item
local function make_item(value, opts)
  local display = opts.format_item and opts.format_item(value) or picker_util.make_display(value)
  display = tostring(display or ""):gsub("[\r\n]+", " ")
  return {
    value = value,
    display = display,
    search = display, -- TODO: ordinal?
  }
end

---@param values any[]
---@param opts   obsidian.picker.ui.Opts
---@return obsidian.picker.ui.Item[]
local function make_items(values, opts)
  return vim.tbl_map(function(value)
    return make_item(value, opts)
  end, values)
end

---@param picker obsidian.picker.ui.Picker
---@return obsidian.picker.ui.Item[]
local function filter_items(picker)
  if picker.query == "" then
    return picker.items
  end

  local items = vim.deepcopy(picker.items)
  local ok, matches = pcall(vim.fn.matchfuzzy, items, picker.query, { key = "search" })
  if ok then
    return matches
  end

  local filtered = {}
  local query = picker.query:lower()
  for _, item in ipairs(picker.items) do
    if item.search:lower():find(query, 1, true) then
      filtered[#filtered + 1] = item
    end
  end
  return filtered
end

---@param picker obsidian.picker.ui.Picker
local function sync_query(picker)
  if vim.api.nvim_buf_is_valid(picker.input_buf) then
    picker.query = vim.api.nvim_buf_get_lines(picker.input_buf, 0, 1, false)[1] or ""
  end
end

---@param picker      obsidian.picker.ui.Picker
---@param match_count integer
---@return obsidian.picker.ui.Layout
local function calculate_layout(picker, match_count)
  local columns = math.max(1, vim.o.columns)
  local available_lines = math.max(1, vim.o.lines - vim.o.cmdheight)
  local has_preview = picker.opts.preview_item ~= nil
  local width_ratio = has_preview and 0.8 or 0.6
  local minimum_width = has_preview and 64 or 40
  local maximum_outer_width = math.max(3, columns - 2)
  local desired_outer_width = math.max(minimum_width, math.floor(columns * width_ratio))
  local title_width = vim.fn.strdisplaywidth(picker.opts.prompt or "Select") + 4
  local outer_width = math.min(maximum_outer_width, math.max(desired_outer_width, title_width))
  local width = math.max(1, outer_width - 2)

  -- All windows share the same width in a vertical stack:
  --   input (3 rows) -> results (body_height + 2) -> preview (preview_height + 2)
  -- Neighbouring windows overlap one border row so they connect seamlessly.
  local max_total_inner = math.max(1, math.floor(available_lines * 0.75))
  local body_height = math.max(1, math.min(picker.max_results, match_count, max_total_inner))
  local preview_height = nil
  local total_outer_height = body_height + 5
  if has_preview then
    preview_height = math.max(3, max_total_inner - body_height)
    total_outer_height = body_height + preview_height + 5
  end
  local row = math.max(0, math.floor((available_lines - total_outer_height) / 2))
  local col = math.max(0, math.floor((columns - outer_width) / 2))

  return {
    row = row,
    col = col,
    width = width,
    body_height = body_height,
    preview_height = preview_height,
  }
end

---@param picker      obsidian.picker.ui.Picker
---@param match_count integer
local function resize(picker, match_count)
  if picker.closed then
    return
  end

  local layout = calculate_layout(picker, match_count)
  if vim.api.nvim_win_is_valid(picker.input_win) then
    vim.api.nvim_win_set_config(picker.input_win, {
      relative = "editor",
      row = layout.row,
      col = layout.col,
      width = layout.width,
      height = 1,
    })
  end
  if vim.api.nvim_win_is_valid(picker.results_win) then
    vim.api.nvim_win_set_config(picker.results_win, {
      relative = "editor",
      row = layout.row + 2,
      col = layout.col,
      width = layout.width,
      height = layout.body_height,
    })
  end
  if picker.preview_win and vim.api.nvim_win_is_valid(picker.preview_win) then
    vim.api.nvim_win_set_config(picker.preview_win, {
      relative = "editor",
      row = layout.row + layout.body_height + 3,
      col = layout.col,
      width = layout.width,
      height = layout.preview_height,
    })
  end
end

---@param picker obsidian.picker.ui.Picker
---@param text   string
local function show_preview_message(picker, text)
  if not picker.preview_win or not picker.preview_buf or not vim.api.nvim_win_is_valid(picker.preview_win) then
    return
  end
  vim.api.nvim_win_set_buf(picker.preview_win, picker.preview_buf)
  vim.api.nvim_set_option_value("modifiable", true, { buf = picker.preview_buf })
  vim.api.nvim_buf_set_lines(picker.preview_buf, 0, -1, false, { text })
  vim.api.nvim_set_option_value("modifiable", false, { buf = picker.preview_buf })
end

---@param picker obsidian.picker.ui.Picker
local function update_preview(picker)
  if not picker.opts.preview_item or not picker.preview_win then
    return
  end

  local item = picker.matches[picker.selection]
  if not item then
    picker.previewed_item = nil
    show_preview_message(picker, "No preview")
    return
  elseif picker.previewed_item == item then
    return
  end
  picker.previewed_item = item

  local ok, spec = pcall(picker.opts.preview_item, item.value)
  if not ok then
    show_preview_message(picker, "Preview failed: " .. tostring(spec))
  elseif not spec or not vim.api.nvim_buf_is_valid(spec.buf) then
    show_preview_message(picker, "No preview")
  else
    local shown, err = pcall(picker_util.show_preview_spec, picker.preview_win, spec)
    if not shown or err ~= true then
      show_preview_message(picker, shown and "No preview" or "Preview failed: " .. tostring(err))
    end
  end
end

---@param picker obsidian.picker.ui.Picker
local function render(picker)
  if picker.closed or not vim.api.nvim_buf_is_valid(picker.results_buf) then
    return
  end

  sync_query(picker)
  picker.matches = filter_items(picker)
  local capacity = calculate_layout(picker, math.max(1, #picker.matches)).body_height
  local visible_count = math.min(capacity, #picker.matches)
  if picker.selection > visible_count then
    picker.selection = visible_count
  end
  if picker.selection < 1 then
    picker.selection = 1
  end

  local lines = {}
  for i = 1, visible_count do
    local item = assert(picker.matches[i], "picker match is missing")
    lines[#lines + 1] = " " .. item.display
  end
  if #lines == 0 then
    lines[1] = "  No results"
  end

  vim.api.nvim_set_option_value("modifiable", true, { buf = picker.results_buf })
  vim.api.nvim_buf_set_lines(picker.results_buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = picker.results_buf })

  -- Place cursor on the selected line so cursorline highlights it.
  if picker.matches[1] and vim.api.nvim_win_is_valid(picker.results_win) then
    vim.api.nvim_win_set_cursor(picker.results_win, { picker.selection, 0 })
  end

  resize(picker, #lines)
  update_preview(picker)
  vim.api.nvim_set_option_value("number", true, { win = picker.preview_win })
end

---@param picker obsidian.picker.ui.Picker
local function restore_focus(picker)
  if vim.api.nvim_win_is_valid(picker.origin_win) then
    vim.api.nvim_set_current_win(picker.origin_win)
  end
end

---@param picker obsidian.picker.ui.Picker
local function close_windows(picker)
  if picker.closed then
    return
  end
  picker.closed = true
  if current == picker then
    current = nil
  end
  if picker.resize_autocmd then
    pcall(vim.api.nvim_del_autocmd, picker.resize_autocmd)
    picker.resize_autocmd = nil
  end

  for _, win in ipairs { picker.results_win, picker.input_win, picker.preview_win } do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs { picker.results_buf, picker.input_buf, picker.preview_buf } do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  restore_focus(picker)
end

---@param buf integer
---@param lhs string | nil
---@param rhs function
local function map(buf, lhs, rhs)
  if lhs and lhs ~= "" then
    vim.keymap.set({ "i", "n" }, lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
end

local function nmap(buf, lhs, rhs)
  if lhs and lhs ~= "" then
    vim.keymap.set({ "n" }, lhs, rhs, { buffer = buf, nowait = true, silent = true })
  end
end

---@param picker obsidian.picker.ui.Picker
local function set_mappings(picker)
  for _, buf in ipairs { picker.input_buf, picker.results_buf } do
    map(buf, "<CR>", function()
      picker:confirm()
    end)
    map(buf, "<Esc>", function()
      picker:cancel()
    end)
    map(buf, "<C-c>", function()
      picker:cancel()
    end)
    nmap(buf, "q", function()
      picker:cancel()
    end)
    map(buf, "<Down>", function()
      picker:move(1)
    end)
    map(buf, "<C-n>", function()
      picker:move(1)
    end)
    map(buf, "<Tab>", function()
      picker:move(1)
    end)
    nmap(buf, "j", function()
      picker:move(1)
    end)
    map(buf, "<Up>", function()
      picker:move(-1)
    end)
    map(buf, "<C-p>", function()
      picker:move(-1)
    end)
    map(buf, "<S-Tab>", function()
      picker:move(-1)
    end)
    nmap(buf, "k", function()
      picker:move(-1)
    end)

    for lhs, mapping in pairs(picker.opts.query_mappings or {}) do
      local query_mapping = mapping
      map(buf, lhs, function()
        picker:run_query_mapping(query_mapping)
      end)
    end
  end
end

---@return any | nil
function PickerUi:selected()
  local item = self.matches[self.selection]
  return item and item.value or nil
end

---@param delta integer
function PickerUi:move(delta)
  if self.closed then
    return
  end
  local limit = math.min(self.max_results, #self.matches)
  if limit == 0 then
    return
  end

  self.selection = self.selection + delta
  if self.selection < 1 then
    self.selection = limit
  elseif self.selection > limit then
    self.selection = 1
  end
  render(self)
end

function PickerUi:confirm()
  if self.closed then
    return
  end
  local choice = self:selected()
  if choice == nil then
    return
  end
  close_windows(self)
  self.on_choice { choice }
end

function PickerUi:cancel()
  if self.closed then
    return
  end
  close_windows(self)
  self.on_choice {}
end

---@param mapping obsidian.PickerMappingOpts
function PickerUi:run_query_mapping(mapping)
  if self.closed then
    return
  end
  sync_query(self)
  if vim.trim(self.query) == "" then
    return
  end

  if mapping.keep_open then
    mapping.callback(self.query)
  else
    local query = self.query
    close_windows(self)
    mapping.callback(query)
  end
end

---@param values any[]
function PickerUi:set_items(values)
  if self.closed then
    return
  end
  self.items = make_items(values, self.opts)
  self.selection = 1
  self.previewed_item = nil
  render(self)
end

---@return string
function PickerUi:get_query()
  sync_query(self)
  return self.query
end

---@param values    any[]
---@param opts      obsidian.picker.ui.Opts | nil
---@param on_choice fun(choices: any[]) | nil
---@return obsidian.picker.ui.Picker
function M.select(values, opts, on_choice)
  opts = opts or {}
  if current then
    current:cancel()
  end

  local input_buf = vim.api.nvim_create_buf(false, true)
  vim.b[input_buf].completion = false -- HACK: for blink.cmp users
  local results_buf = vim.api.nvim_create_buf(false, true)
  local preview_buf = opts.preview_item and vim.api.nvim_create_buf(false, true) or nil
  set_scratch_buf_opts(input_buf, "wipe")
  set_scratch_buf_opts(results_buf, "wipe")
  if preview_buf then
    set_scratch_buf_opts(preview_buf, "hide")
  end

  local picker = setmetatable({
    input_buf = input_buf,
    results_buf = results_buf,
    preview_buf = preview_buf,
    origin_win = vim.api.nvim_get_current_win(),
    opts = opts,
    on_choice = on_choice or function() end,
    items = make_items(values, opts),
    matches = {},
    selection = 1,
    max_results = math.max(1, opts.max_results or default_max_results),
    query = opts.query or "",
    closed = false,
  }, PickerUi)
  ---@cast picker obsidian.picker.ui.Picker

  vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, { picker.query })
  picker.matches = filter_items(picker)
  local initial_height = math.max(1, math.min(picker.max_results, #picker.matches))
  local layout = calculate_layout(picker, initial_height)
  local title = opts.prompt or "Select"

  -- Border shapes for a vertical stack where neighbouring windows share
  -- a border row: rounded top on input, rounded bottom on the last window,
  -- T-junctions (├┤) everywhere else so the panels connect seamlessly.
  ---@type string[]
  local input_border = { "╭", "─", "╮", "│", "┤", "─", "├", "│" }
  ---@type string[]
  local results_border = preview_buf and { "├", "─", "┤", "│", "┤", "─", "├", "│" } -- top + bottom T-junctions
    or { "├", "─", "┤", "│", "╯", "─", "╰", "│" } -- top T, bottom rounded
  ---@type string[]
  local preview_border = { "├", "─", "┤", "│", "╯", "─", "╰", "│" } -- top T, bottom rounded

  picker.input_win = vim.api.nvim_open_win(input_buf, true, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = 1,
    style = "minimal",
    border = input_border,
    title = " " .. title .. " ",
    title_pos = "left",
  })
  picker.results_win = vim.api.nvim_open_win(results_buf, false, {
    relative = "editor",
    row = layout.row + 2,
    col = layout.col,
    width = layout.width,
    height = layout.body_height,
    style = "minimal",
    border = results_border,
  })
  if preview_buf then
    picker.preview_win = vim.api.nvim_open_win(preview_buf, false, {
      relative = "editor",
      row = layout.row + layout.body_height + 3,
      col = layout.col,
      width = layout.width,
      height = layout.preview_height,
      style = "minimal",
      border = preview_border,
      title = " Preview ",
      title_pos = "left",
    })
  end

  set_float_win_opts(picker.input_win)
  set_float_win_opts(picker.results_win)
  vim.api.nvim_set_option_value("cursorline", true, { win = picker.results_win })
  if picker.preview_win then
    set_float_win_opts(picker.preview_win)
  end

  current = picker
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = input_buf,
    callback = function()
      vim.schedule(function()
        if not picker.closed then
          picker.selection = 1
          render(picker)
        end
      end)
    end,
  })
  picker.resize_autocmd = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      vim.schedule(function()
        if not picker.closed then
          render(picker)
        end
      end)
    end,
  })

  set_mappings(picker)
  render(picker)
  vim.schedule(function()
    if not picker.closed and vim.api.nvim_win_is_valid(picker.input_win) then
      vim.api.nvim_set_current_win(picker.input_win)
      vim.api.nvim_win_set_cursor(picker.input_win, { 1, #picker.query })
      vim.cmd "startinsert!"
    end
  end)

  return picker
end

return M
