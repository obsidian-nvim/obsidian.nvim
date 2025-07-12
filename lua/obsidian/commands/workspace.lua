local log = require "obsidian.log"
local Workspace = require "obsidian.workspace"

---@param workspace obsidian.Workspace|string The workspace object or the name of an existing workspace.
---@param opts { lock: boolean|? }|?
local switch_workspace = function(workspace, opts)
  opts = opts and opts or {}

  if workspace == Obsidian.workspace.name then
    log.info("Already in workspace '%s' @ '%s'", workspace, Obsidian.workspace.path)
    return
  end

  for _, ws in ipairs(Obsidian.opts.workspaces) do
    if ws.name == workspace then
      return Workspace.set(Workspace.new_from_spec(ws), opts)
    end
  end

  error(string.format("Workspace '%s' not found", workspace))
end

---@param data CommandArgs
return function(_, data)
  if not data.args or string.len(data.args) == 0 then
    local picker = Obsidian.picker
    if not picker then
      log.info("Current workspace: '%s' @ '%s'", Obsidian.workspace.name, Obsidian.workspace.path)
      return
    end

    local options = {}
    for i, spec in ipairs(Obsidian.opts.workspaces) do
      local workspace = Workspace.new_from_spec(spec)
      if workspace == Obsidian.workspace then
        options[#options + 1] = string.format("*[%d] %s @ '%s'", i, workspace.name, workspace.path)
      else
        options[#options + 1] = string.format("[%d] %s @ '%s'", i, workspace.name, workspace.path)
      end
    end

    picker:pick(options, {
      prompt_title = "Workspaces",
      callback = function(workspace_str)
        local idx = tonumber(string.match(workspace_str, "%*?%[(%d+)]"))
        switch_workspace(Obsidian.opts.workspaces[idx].name, { lock = true })
      end,
    })
  else
    switch_workspace(data.args, { lock = true })
  end
end
