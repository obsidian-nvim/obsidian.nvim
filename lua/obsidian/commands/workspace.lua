local Workspace = require "obsidian.workspace"

---@param data obsidian.CommandArgs
return function(data)
  if not data.args or string.len(data.args) == 0 then
    local picker = Obsidian.picker
    if picker then
      ---@type obsidian.PickerEntry
      local options = vim.tbl_map(function(ws)
        return {
          value = ws,
          display = tostring(ws),
          filename = tostring(ws.path),
        }
      end, Obsidian.workspaces)
      picker:pick(options, {
        prompt_title = "Obsidian Workspace",
        callback = function(entry)
          Workspace.set(entry.value.name)
        end,
      })
    else
      vim.ui.select(Obsidian.workspaces, {
        prompt = "Obsidian Workspace",
        format_item = tostring,
      }, function(ws)
        if not ws then
          return
        end
        Workspace.set(ws.name)
      end)
    end
  else
    Workspace.set(data.args)
  end
end
