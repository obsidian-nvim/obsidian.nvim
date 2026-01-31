local M = {}

local api = require "obsidian.api"
local util = require "obsidian.util"
local Path = require "obsidian.path"

---@param opts { prompt_title: string }|?
---@return string
M.build_prompt = function(opts)
  opts = opts or {}

  ---@type string
  local prompt = opts.prompt_title or "Find"
  if string.len(prompt) > 50 then
    prompt = string.sub(prompt, 1, 50) .. "…"
  end

  prompt = prompt .. " | <CR> confirm"

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

  if entry.filename then
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
