local Workspace = require "obsidian.workspace"
local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  if not data.args or string.len(data.args) == 0 then
    ---@type obsidian.PickerEntry[]
    local items = vim.tbl_map(function(ws)
      if ws.name == ".obsidian.wiki" then
        return
      end
      return {
        user_data = ws,
        text = tostring(ws),
        filename = tostring(ws.path),
      }
    end, Obsidian.workspaces)
    picker.select(items, { prompt = "Obsidian Workspace" }, function(choices)
      local entry = choices[1]
      if entry then
        Workspace.set(entry.user_data)
      end
    end)
  else
    Workspace.set(data.args)
  end
end
