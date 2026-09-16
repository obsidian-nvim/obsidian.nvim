local Workspace = require "obsidian.workspace"
local picker = require "obsidian.picker"

---@param data obsidian.CommandArgs
return function(data)
  if not data.args or string.len(data.args) == 0 then
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
    picker.select(items, {
      prompt = "Obsidian Workspace",
      format_item = function(entry)
        return entry.text
      end,
      preview_item = function(entry)
        return picker.preview_path(entry.filename)
      end,
    }, function(choices)
      local entry = choices[1]
      if entry then
        Workspace.set(entry.user_data)
      end
    end)
  else
    Workspace.set(data.args)
  end
end
