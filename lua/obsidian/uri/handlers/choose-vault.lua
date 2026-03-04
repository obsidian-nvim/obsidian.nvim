--- Handle the "choose-vault" action.
---@param _ obsidian.uri.Parsed
local function handle_choose_vault(_)
  local Workspace = require "obsidian.workspace"

  ---@type obsidian.PickerEntry[]
  local items = {}
  for _, ws in ipairs(Obsidian.workspaces) do
    if ws.name ~= ".obsidian.wiki" then
      items[#items + 1] = {
        user_data = ws,
        text = tostring(ws),
        filename = tostring(ws.path),
      }
    end
  end

  Obsidian.picker.pick(items, {
    prompt_title = "Obsidian Workspace",
    callback = function(entry)
      Workspace.set(entry.user_data)
    end,
  })
end

return handle_choose_vault
