local api = require "obsidian.api"
local highlights = require "obsidian.highlights"
local log = require "obsidian.log"
local picker = require "obsidian.picker"

---@param items obsidian.HighlightLocation[]
---@param bufnr integer?
local function pick(items, bufnr)
  if #items == 0 then
    log.info(bufnr and "No highlights in current note" or "No highlights in vault")
    return
  end

  local vault_dir = api.resolve_workspace_dir()
  picker.select(items, {
    prompt = "Highlights",
    format_item = function(item)
      local position = ("%d:%d"):format(item.lnum, item.col)
      if bufnr then
        return ("%s  %s"):format(position, item.text)
      end
      local path = item.path and item.path:relative_to(vault_dir) or item.filename
      return ("%s:%s  %s"):format(tostring(path), position, item.text)
    end,
    preview_item = function(item)
      local preview
      if bufnr then
        preview = { buf = bufnr }
      else
        preview = picker.preview_path(assert(item.filename, "highlight path is missing"))
      end
      preview.pos = { item.range.start_row + 1, item.range.start_col }
      preview.pos_end = { item.range.end_row + 1, item.range.end_col }
      return preview
    end,
  }, function(selected)
    local item = selected and selected[1]
    if not item or (bufnr and not vim.api.nvim_buf_is_valid(bufnr)) then
      return
    end
    api.open_note(item)
  end)
end

---@param data obsidian.CommandArgs?
return function(data)
  local arg = data and data.args or ""
  if arg == "%" then
    local bufnr = vim.api.nvim_get_current_buf()
    pick(highlights.find_buffer(bufnr), bufnr)
  elseif arg == "" then
    return highlights.find_vault_async(pick)
  else
    log.err("Invalid highlights target '%s' (expected '%%')", arg)
  end
end
