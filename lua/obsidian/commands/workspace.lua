local Workspace = require "obsidian.workspace"
local log = require "obsidian.log"

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
          filename = ws:is_resolved() and tostring(ws.path) or nil,
        }
      end
    end
    Obsidian.picker.pick(items, {
      prompt_title = "Obsidian Workspace",
      callback = function(entry)
        local ws = entry.user_data
        if not ws:is_resolved() then
          if not ws:resolve() then
            log.err("Workspace '%s' could not be resolved", ws.name)
            return
          end
        end
        Workspace.set(ws)
      end,
    })
  else
    Workspace.set(data.args)
  end
end
