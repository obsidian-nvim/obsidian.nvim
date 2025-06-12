local M = {}
local api = require "obsidian.api"

---builtin functions that are default values for actions, and modules

M.gf_passthrough = function()
  local legacy = require("obsidian").get_client().opts.legacy_commands
  if api.cursor_on_markdown_link(nil, nil, true) then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  else
    return "gf"
  end
end

M.smart_action = function()
  local legacy = require("obsidian").get_client().opts.legacy_commands
  -- follow link if possible
  if api.cursor_on_markdown_link(nil, nil, true) then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  end

  -- show notes with tag if possible
  if api.cursor_tag(nil, nil) then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  end

  if api.cursor_heading() then
    return "za"
  end

  -- toggle task if possible
  -- cycles through your custom UI checkboxes, default: [ ] [~] [>] [x]
  return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
end

---Create a new unique Zettel ID.
---
---@return string
M.zettel_id = function()
  local suffix = ""
  for _ = 1, 4 do
    suffix = suffix .. string.char(math.random(65, 90))
  end
  return tostring(os.time()) .. "-" .. suffix
end

return M
