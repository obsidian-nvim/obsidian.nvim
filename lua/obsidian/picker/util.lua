local M = {}

local api = require "obsidian.api"
local util = require "obsidian.util"
local Path = require "obsidian.path"

---@param opts { prompt_title: string, query_mappings: obsidian.PickerMappingTable|?, selection_mappings: obsidian.PickerMappingTable|? }|?
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

---@param entry obsidian.PickerEntry
---
---@return string, { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
M.make_display = function(entry)
  local buf = {}
  ---@type { [1]: { [1]: integer, [2]: integer }, [2]: string }[]
  local highlights = {}

  local icon, icon_hl

  if entry.icon then
    icon = entry.icon
    icon_hl = entry.icon_hl
  elseif entry.filename then
    icon, icon_hl = api.get_icon(entry.filename)
  end

  if icon then
    buf[#buf + 1] = icon
    buf[#buf + 1] = " "
    if icon_hl then
      highlights[#highlights + 1] = { { 0, util.strdisplaywidth(icon) }, icon_hl }
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

  if entry.display then
    buf[#buf + 1] = " "
    buf[#buf + 1] = entry.display
  elseif entry.value then
    buf[#buf + 1] = " "
    buf[#buf + 1] = tostring(entry.value)
  end

  return table.concat(buf, ""), highlights
end

return M
