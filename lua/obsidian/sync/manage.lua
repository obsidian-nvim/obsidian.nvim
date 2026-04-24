local log = require "obsidian.log"

local M = {}

--- Build a lookup from workspace root path -> remote vault name.
--- Obsidian-backend specific helper, kept here for backward compatibility.
---@param local_vaults table<string, obsidian.sync.LocalVault>
---@param remotes obsidian.sync.RemoteVault[]?
---@return table<string, string>
function M.build_linked_map(local_vaults, remotes)
  local remote_by_id = {}
  if remotes then
    for _, r in ipairs(remotes) do
      remote_by_id[r.hash] = r.name
    end
  end

  local map = {}
  for vault_path, vault in pairs(local_vaults) do
    map[vault_path] = remote_by_id[vault.hash] or vault.hash
  end
  return map
end

---@param ws obsidian.Workspace
local function ws_label(ws)
  return string.format("%s (%s)", ws.name, tostring(ws.root))
end

function M.setup()
  local workspaces = Obsidian.workspaces
  if not workspaces or #workspaces == 0 then
    log.err "No workspaces configured."
    return
  end

  local backend = require("obsidian.sync").get_backend()
  if not backend then
    return
  end

  if #workspaces == 1 then
    backend.setup(workspaces[1])
    return
  end

  vim.ui.select(workspaces, {
    prompt = "Select workspace to set up sync for",
    format_item = ws_label,
  }, function(ws)
    if ws then
      backend.setup(ws)
    end
  end)
end

function M.disconnect()
  local workspaces = Obsidian.workspaces
  if not workspaces or #workspaces == 0 then
    log.err "No workspaces configured."
    return
  end

  local backend = require("obsidian.sync").get_backend()
  if not backend then
    return
  end

  local linked = vim.tbl_filter(function(ws)
    return backend.is_configured(ws)
  end, workspaces)

  if #linked == 0 then
    log.info "No workspaces are linked."
    return
  end

  vim.ui.select(linked, {
    prompt = "Select workspace to unlink",
    format_item = ws_label,
  }, function(ws)
    if ws then
      backend.disconnect(ws)
    end
  end)
end

return M
