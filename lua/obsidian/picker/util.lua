local preview_ns = vim.api.nvim_create_namespace "obsidian.picker.preview"

local icons = require "obsidian.icons"
local Path = require "obsidian.path"

local M = {}

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

---Open one picker result directly, or put multiple results in the quickfix list.
---@param entries (string|obsidian.PickerEntry)[]
M.open_notes = function(entries)
  if #entries == 0 then
    return
  elseif #entries == 1 then
    require("obsidian.api").open_note(entries[1])
    return
  end

  local items = vim.tbl_map(function(entry)
    if type(entry) == "string" then
      return { filename = entry }
    else
      return entry
    end
  end, entries)
  vim.fn.setqflist(items, "r")
  vim.cmd "copen"
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

  return table.concat(buf, "")
end

return M
