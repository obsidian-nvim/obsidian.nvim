local Workspace = require "obsidian.workspace"

---@param data obsidian.commands.Args
return function(data)
  if not data.args or data.args == "" then
    Workspace.pick()
  else
    Workspace.set(data.args)
  end
end
