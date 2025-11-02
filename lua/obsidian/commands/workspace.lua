local Workspace = require "obsidian.workspace"

---@param data obsidian.CommandArgs
return function(data)
  if not data.args or string.len(data.args) == 0 then
    ---@type obsidian.PickerEntry
    local options = vim.tbl_map(function(ws)
      return {
        user_data = ws,
        text = tostring(ws),
        filename = tostring(ws.path),
      }
    end, Obsidian.workspaces)
    Obsidian.picker.pick(options, {
      prompt_title = "Obsidian Workspace",
      callback = function(entry)
        Workspace.set(entry.user_data)
      end,
    })
  else
    Workspace.set(data.args)
  end
end
