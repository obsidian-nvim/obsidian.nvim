local ut = require "obsidian.uri.util"

--- Handle the `choose-vault` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_choose_vault(parsed)
  local Workspace = require "obsidian.workspace"

  ---@type obsidian.PickerEntry[]
  local items = {}
  for _, workspace in ipairs(Obsidian.workspaces) do
    if workspace.name ~= ".obsidian.wiki" then
      items[#items + 1] = {
        user_data = workspace,
        text = tostring(workspace),
        filename = tostring(workspace.path),
      }
    end
  end

  Obsidian.picker.pick(items, {
    prompt_title = "Obsidian Workspace",
    callback = function(entry)
      Workspace.set(entry.user_data)
    end,
  })
  return ut.success(parsed, { interactive = true })
end

return handle_choose_vault
