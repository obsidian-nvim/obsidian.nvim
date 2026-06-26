local M = {}

local preview_ns = vim.api.nvim_create_namespace "obsidian.picker.preview"

local api = require "obsidian.api"
local util = require "obsidian.util"
local Path = require "obsidian.path"

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

---@param spec obsidian.ui.select_preview_spec|?
---@return boolean
M.valid_preview_spec = function(spec)
  return type(spec) == "table" and type(spec.buf) == "number" and vim.api.nvim_buf_is_valid(spec.buf)
end

---@param winid integer
---@param spec obsidian.ui.select_preview_spec|?
---@return boolean
M.show_preview_spec = function(winid, spec)
  if not M.valid_preview_spec(spec) or not vim.api.nvim_win_is_valid(winid) then
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

---@param spec obsidian.ui.select_preview_spec|?
---@return table
M.preview_spec_to_fzf_entry = function(spec)
  if not M.valid_preview_spec(spec) then
    return {}
  end

  local pos = spec.pos or { 1, 0 }
  local pos_end = spec.pos_end
  return {
    _scratch_buf = spec.buf,
    line = pos[1] or 1,
    col = (pos[2] or 0) + 1,
    end_line = pos_end and pos_end[1] or nil,
    end_col = pos_end and (pos_end[2] or 0) + 1 or nil,
  }
end

---@param entry obsidian.PickerEntry
---
---@return string, { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
M.make_display = function(entry)
  local buf = {}
  ---@type { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
  local highlights = {}

  local icon, icon_hl

  if entry.filename then
    icon, icon_hl = api.get_icon(entry.filename)
  end

  if icon then
    buf[#buf + 1] = icon
    buf[#buf + 1] = " "
    if icon_hl then
      local icon_width = util.strdisplaywidth(icon)
      ---@cast icon_width integer
      highlights[#highlights + 1] = { { 0, icon_width }, icon_hl }
    end
  end

  if entry.filename then
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

  if entry.text then
    buf[#buf + 1] = " "
    buf[#buf + 1] = entry.text
  elseif entry.user_data then
    buf[#buf + 1] = " "
    buf[#buf + 1] = tostring(entry.user_data)
  end

  return table.concat(buf, ""), highlights
end

return M
