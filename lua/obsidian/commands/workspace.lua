local Workspace = require "obsidian.workspace"

---@param data CommandArgs
return function(_, data)
  if not data.args or string.len(data.args) == 0 then
    vim.ui.select(Obsidian.workspaces, {
      prompt = "Obsidian Workspace",
      format_item = function(ws)
        if ws.name == Obsidian.workspace.name then
          return string.format("*[%s] @ '%s'", ws.name, ws.path)
        end
        return string.format("[%s] @ '%s'", ws.name, ws.path)
      end,
    }, function(item)
      if not item then
        return
      end
      Workspace.switch(item.name, { lock = true })
    end)
  else
    Workspace.switch(data.args, { lock = true })
  end
end
