--- Status indicator for sync

---@type table<string, string>
local sync_status = {}

local sync_icons = {
  synced = "󰸞",
  syncing = "󰑓",
  paused = "󰏤",
}

local group = {
  synced = "DiagnosticOk",
  syncing = "DiagnosticWarn",
  paused = "DiagnosticInfo",
}

vim.g.obsidian_sync_status_kind = "paused"
vim.g.obsidian_sync_status_icon = ""
vim.g.obsidian_sync_status = ""

local function status_color()
  local workspace = Obsidian and Obsidian.workspace or nil
  local key = workspace and tostring(workspace.root) or nil
  local kind = key and sync_status[key] or nil

  local hl = group[kind]
  return hl or "DiagnosticInfo"
end

---@param kind? "synced" | "syncing" | "paused"
local function set_statusline_globals(kind)
  local icon = (kind and sync_icons[kind]) or ""
  local hl = group[kind] or "DiagnosticInfo"

  vim.g.obsidian_sync_status_kind = kind
  vim.g.obsidian_sync_status_icon = icon
  vim.g.obsidian_sync_status = icon ~= "" and string.format(" %%#%s# %s %%*", hl, icon) or ""
end

---@param workspace obsidian.Workspace
---@param kind "synced" | "syncing" | "paused"
local function set_status(workspace, kind)
  local key = tostring(workspace.root)
  sync_status[key] = kind

  local current = Obsidian and Obsidian.workspace or nil
  if not current or tostring(current.root) ~= key then
    return
  end

  set_statusline_globals(kind)
end

return {
  set = set_status,
  color = status_color,
}
