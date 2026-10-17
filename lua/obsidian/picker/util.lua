local preview_ns = vim.api.nvim_create_namespace "obsidian.picker.preview"

local icons = require "obsidian.icons"
local Path = require "obsidian.path"
local preview = require "obsidian.preview"
local Range = require "obsidian.range"

local M = {}

---@param path string|obsidian.Path
---@return obsidian.ui_select_preview_spec
M.preview_path = function(path)
  return preview.path(path)
end

---@param entry obsidian.PickerEntry
---@return obsidian.ui_select_preview_spec
M.preview_entry = function(entry)
  if type(entry) ~= "table" then
    return preview.text { "Preview unavailable: item is not a file" }
  end
  return preview.location {
    path = entry.filename,
    bufnr = entry.bufnr,
    lnum = entry.lnum,
    col = entry.col,
    end_lnum = entry.end_lnum,
    end_col = entry.end_col,
    range = rawget(entry, "range"),
    encoding = rawget(entry, "encoding"),
  }
end

---@param opts { prompt_title: string|?, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|? }|?
---@return string
M.build_prompt = function(opts)
  opts = opts or {}

  ---@type string
  local prompt = opts.prompt_title or "Find"
  if string.len(prompt) > 50 then
    prompt = string.sub(prompt, 1, 50) .. "…"
  end

  prompt = prompt .. " | <CR> confirm"

  if opts.query_mappings then
    local keys = vim.tbl_keys(opts.query_mappings)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local mapping = opts.query_mappings[key]
      prompt = prompt .. " | " .. key .. " " .. mapping.desc
    end
  end

  if opts.selection_mappings then
    local keys = vim.tbl_keys(opts.selection_mappings)
    table.sort(keys)
    for _, key in ipairs(keys) do
      local mapping = opts.selection_mappings[key]
      prompt = prompt .. " | " .. key .. " " .. mapping.desc
    end
  end

  return prompt
end

---@param winid integer
---@param spec obsidian.ui_select_preview_spec|?
---@return boolean
M.show_preview_spec = function(winid, spec)
  if not spec or not vim.api.nvim_win_is_valid(winid) then
    return false
  end

  local buf = spec.buf
  vim.api.nvim_win_set_buf(winid, buf)
  vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)

  if spec.pos then
    local lnum = math.max(spec.pos[1] or 1, 1)
    local col = math.max(spec.pos[2] or 0, 0)
    pcall(vim.api.nvim_win_set_cursor, winid, { lnum, col })
    pcall(vim.api.nvim_win_call, winid, function()
      vim.cmd "normal! zt"
    end)

    if spec.pos_end then
      pcall(vim.api.nvim_buf_set_extmark, buf, preview_ns, lnum - 1, col, {
        end_row = math.max(spec.pos_end[1] or lnum, 1) - 1,
        end_col = math.max(spec.pos_end[2] or col + 1, 0),
        hl_group = "Visual",
      })
    else
      pcall(vim.api.nvim_buf_set_extmark, buf, preview_ns, lnum - 1, 0, {
        line_hl_group = "CursorLine",
      })
    end
  end

  return true
end

---@class obsidian.picker.QuickfixOpts
---@field title? string
---@field strings_are_paths? boolean
---@field eligible? fun(value: any): boolean
---@field to_entry? fun(value: any): obsidian.PickerEntry?

---@param entry any
---@param opts obsidian.picker.QuickfixOpts
---@return obsidian.PickerEntry|?
local function to_quickfix_entry(entry, opts)
  if opts.eligible and not opts.eligible(entry) then
    return nil
  end
  if type(entry) == "string" then
    if not opts.strings_are_paths then
      return nil
    end
    entry = { filename = entry }
  elseif opts.to_entry then
    entry = opts.to_entry(entry)
  end
  if type(entry) ~= "table" or type(entry.filename) ~= "string" or entry.filename == "" then
    return nil
  end

  local item = {
    filename = entry.filename,
    lnum = entry.lnum,
    col = entry.col,
    end_lnum = entry.end_lnum,
    end_col = entry.end_col,
    text = entry.text or entry.link or entry.display_name or entry.filename,
    user_data = entry.user_data or entry,
  }
  local range = rawget(entry, "range")
  if type(range) == "table" then
    if type(range.start_row) == "number" then
      item.lnum = range.start_row + 1
      item.col = range.start_col + 1
      item.end_lnum = range.end_row + 1
      item.end_col = range.end_col + 1
    elseif range.start and range["end"] then
      local lines = preview.read_path(entry.filename)
      local native = Range.from_lsp(range, entry.encoding or "utf-16", lines)
      item.lnum = native.start_row + 1
      item.col = native.start_col + 1
      item.end_lnum = native.end_row + 1
      item.end_col = native.end_col + 1
    end
  end
  return item
end

---Create a new titled quickfix list and open it, preserving list history.
---@param entries any[]
---@param opts obsidian.picker.QuickfixOpts|?
---@return boolean
M.send_to_qf = function(entries, opts)
  opts = opts or {}
  local items = {}
  for _, entry in ipairs(entries or {}) do
    local item = to_quickfix_entry(entry, opts)
    if item then
      items[#items + 1] = item
    end
  end
  if #items == 0 then
    return false
  end

  vim.fn.setqflist({}, " ", { title = opts.title or "Obsidian results", items = items })
  vim.cmd "copen"
  return true
end

---Build the standard `<C-q>` quickfix selection mapping.
---@param opts obsidian.picker.QuickfixOpts|?
---@return obsidian.PickerMappingOpts
M.send_to_qf_mapping = function(opts)
  opts = opts or {}
  return {
    desc = "send to quickfix",
    allow_multiple = true,
    quickfix = opts,
    callback = function(first, ...)
      local entries = { first, ... }
      M.send_to_qf(entries, opts)
    end,
  }
end

---Open one picker result directly, or export multiple file/location results to quickfix.
---@param entries any[]
---@param opts obsidian.picker.QuickfixOpts|?
M.open_notes = function(entries, opts)
  opts = opts or {}
  if #entries == 0 then
    return
  elseif #entries == 1 then
    local entry = entries[1]
    if type(entry) == "string" then
      if not opts.strings_are_paths then
        return
      end
      entry = { filename = entry }
    end
    if type(entry) ~= "table" or type(entry.filename) ~= "string" then
      return
    end
    require("obsidian.api").open_note(entry)
    return
  end

  M.send_to_qf(entries, opts)
end

---@param entry obsidian.PickerEntry|string
---
---@return string
M.make_display = function(entry)
  if type(entry) == "string" then
    return entry
  end

  local buf = {}
  local icon = icons.get_icon(entry)

  if icon then
    buf[#buf + 1] = icon
    buf[#buf + 1] = " "
  end

  if entry.text then
    buf[#buf + 1] = entry.text
  elseif entry.filename then
    buf[#buf + 1] = Path.new(entry.filename):vault_relative_path()

    if entry.lnum ~= nil then
      buf[#buf + 1] = ":"
      buf[#buf + 1] = entry.lnum

      if entry.col ~= nil then
        buf[#buf + 1] = ":"
        buf[#buf + 1] = entry.col
      end
    end
  end

  return table.concat(buf, "")
end

return M
