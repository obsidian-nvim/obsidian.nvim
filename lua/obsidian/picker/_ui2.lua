local M = {}

local api = require "obsidian.api"
local Path = require "obsidian.path"
local Picker = require "obsidian.picker"
local QuickSwitch = require "obsidian.completion.sources.quick_switch"

local current

---@param buf integer
local function set_buf_opts(buf)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
end

---@param win integer
local function set_win_opts(win)
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
  vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
  vim.api.nvim_set_option_value("wrap", false, { win = win })
  vim.api.nvim_set_option_value("spell", false, { win = win })
end

---@return integer, integer, integer
local function layout()
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight
  local width = math.min(math.max(20, columns - 4), math.max(40, math.floor(columns * 0.6)))
  local row = math.max(1, math.floor(lines * 0.18))
  local col = math.max(0, math.floor((columns - width) / 2))
  return row, col, width
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

  QuickSwitch.unregister(picker.buf)

  if picker.win and vim.api.nvim_win_is_valid(picker.win) then
    pcall(vim.api.nvim_win_close, picker.win, true)
  end
  if picker.buf and vim.api.nvim_buf_is_valid(picker.buf) then
    pcall(vim.api.nvim_buf_delete, picker.buf, { force = true })
  end

  if restore and picker.origin_win and vim.api.nvim_win_is_valid(picker.origin_win) then
    vim.api.nvim_set_current_win(picker.origin_win)
  end
end

local function close_current()
  if current then
    close_picker(current, true)
  end
end

---@param picker table
---@param entry obsidian.PickerEntry
local function choose(picker, entry)
  close_picker(picker, true)

  if picker.callback then
    picker.callback(entry.filename)
  else
    api.open_note(entry)
  end
end

---@param bufnr integer
---@param label string
---@return boolean handled
function M.accept_completion(bufnr, label)
  local picker = current
  if not picker or picker.closed or picker.buf ~= bufnr then
    return false
  end

  local entry = QuickSwitch.resolve_label(bufnr, label)
  if not entry then
    return false
  end

  choose(picker, entry)
  return true
end

---@param picker table
local function complete(picker)
  if picker.closed or not vim.api.nvim_buf_is_valid(picker.buf) then
    return
  end
  if vim.api.nvim_get_current_buf() ~= picker.buf then
    return
  end

  if vim.lsp.completion and vim.lsp.completion.get then
    pcall(vim.lsp.completion.get)
  elseif vim.fn.mode() == "i" and vim.fn.pumvisible() == 0 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-x><C-o>", true, false, true), "n", false)
  end
end

---@param picker table
---@return obsidian.PickerEntry|?
local function resolve_line(picker)
  local line = vim.api.nvim_buf_get_lines(picker.buf, 0, 1, false)[1] or ""
  if line == "" then
    return nil
  end

  return QuickSwitch.resolve_label(picker.buf, line)
end

local function confirm_current()
  local picker = current
  if not picker or picker.closed then
    return
  end

  if vim.fn.pumvisible() == 1 then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-y>", true, false, true), "n", false)
    return
  end

  local entry = resolve_line(picker)
  if entry then
    choose(picker, entry)
  else
    complete(picker)
  end
end

---@param picker table
---@param callback function
---@param ... any
local function close_and_call(picker, callback, ...)
  local args = { ... }
  close_picker(picker, true)
  callback(unpack(args))
end

---@param picker table
---@param mapping obsidian.PickerMappingOpts
local function run_query_mapping(picker, mapping)
  local query = vim.api.nvim_buf_get_lines(picker.buf, 0, 1, false)[1] or ""
  if vim.trim(query) == "" then
    return
  end

  if mapping.keep_open then
    mapping.callback(query)
  else
    close_and_call(picker, mapping.callback, query)
  end
end

---@param picker table
local function set_mappings(picker)
  vim.keymap.set({ "i", "n" }, "<CR>", confirm_current, { buffer = picker.buf, nowait = true, silent = true })
  vim.keymap.set({ "i", "n" }, "<Esc>", close_current, { buffer = picker.buf, nowait = true, silent = true })
  vim.keymap.set({ "i", "n" }, "<C-c>", close_current, { buffer = picker.buf, nowait = true, silent = true })
  vim.keymap.set("n", "q", close_current, { buffer = picker.buf, nowait = true, silent = true })

  for key, mapping in pairs(picker.query_mappings or {}) do
    vim.keymap.set({ "i", "n" }, key, function()
      run_query_mapping(picker, mapping)
    end, { buffer = picker.buf, nowait = true, silent = true })
  end
end

---@param picker table
local function start_lsp_completion(picker)
  if not Obsidian then
    return
  end

  local client_id = require("obsidian.lsp").start(picker.buf)
  if not client_id then
    return
  end

  local client = vim.lsp.get_client_by_id(client_id)
  if client and client.server_capabilities.completionProvider then
    local chars = {}
    for i = 32, 126 do
      chars[#chars + 1] = string.char(i)
    end
    client.server_capabilities.completionProvider.triggerCharacters = chars
  end

  pcall(vim.api.nvim_set_option_value, "completeopt", "menuone,fuzzy", { buf = picker.buf })
  vim.api.nvim_set_option_value("omnifunc", "v:lua.vim.lsp.omnifunc", { buf = picker.buf })

  if vim.lsp.completion and vim.lsp.completion.enable then
    pcall(vim.lsp.completion.enable, true, client_id, picker.buf, { autotrigger = true })
  end
end

--- Find notes from a floating markdown input buffer backed by LSP completion.
---
---@param opts obsidian.PickerFindOpts|? Options.
M.find_files = function(opts)
  Picker.state.calling_bufnr = vim.api.nvim_get_current_buf()

  opts = opts or {}

  if current then
    close_picker(current, false)
  end

  ---@type obsidian.Path
  local dir = opts.dir and Path.new(opts.dir) or Obsidian.dir
  local origin_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".md")
  set_buf_opts(buf)

  local row, col, width = layout()
  local title = opts.prompt_title or "Quick Switch"
  local win = vim.api.nvim_open_win(buf, true, {
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

  set_win_opts(win)

  local picker = {
    buf = buf,
    win = win,
    origin_win = origin_win,
    callback = opts.callback,
    query_mappings = opts.query_mappings,
  }
  current = picker

  QuickSwitch.register(buf, { dir = dir })
  vim.b[buf].obsidian_completion_source = "quick_switch"

  if opts.query and opts.query ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.query })
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      QuickSwitch.unregister(buf)
    end,
  })

  set_mappings(picker)
  start_lsp_completion(picker)

  vim.schedule(function()
    if not picker.closed and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
      local query = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
      vim.api.nvim_win_set_cursor(win, { 1, #query })
      vim.cmd "startinsert!"
    end
  end)
end

M.pick = require("obsidian.picker._default").pick

-- Grep is intentionally the native implementation for now.
M.grep = require("obsidian.picker._default").grep

return M
