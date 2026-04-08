local sync_icons = {
  synced = "󰸞",
  syncing = "󰑓",
  paused = "󰏤",
}

local group = {
  synced = "ObsidianSyncSynced",
  syncing = "ObsidianSyncSyncing",
  paused = "ObsidianSyncPaused",
}

local default_links = {
  ObsidianSyncSynced = "DiagnosticOk",
  ObsidianSyncSyncing = "DiagnosticWarn",
  ObsidianSyncPaused = "DiagnosticInfo",
}

---@alias obsidian.sync.StatusKind "synced" | "syncing" | "paused"

for group_name, link in pairs(default_links) do
  vim.api.nvim_set_hl(0, group_name, { default = true, link = link })
end

local state = {
  ---@type obsidian.sync.StatusKind
  kind = "paused",
  icon = "",
  need_update = true,
}

vim.g.obsidian_sync_status = ""

local function color()
  local hl = group[state.kind]
  return hl or group.paused
end

---@param kind obsidian.sync.StatusKind
local function set(kind)
  if kind == "syncing" and state.kind == "paused" then -- HACK:
    return
  end

  state.kind = kind
  local icon = (kind and sync_icons[kind]) or ""
  state.icon = icon
  state.need_update = true
end

local function component()
  local hl = color()
  local icon = state.icon
  return icon ~= "" and string.format(" %%#%s# %s %%*", hl, icon) or ""
end

local function icon()
  return state.icon
end

local function cond()
  if state.need_update then
    return true
  end
  state.need_update = false
end

return {
  set = set,
  color = color,
  icon = icon,
  cond = cond,
  component = component,
  state = state,
}
