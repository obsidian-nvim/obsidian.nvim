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

---@alias obsidian.sync.StatusKind "synced" | "syncing" | "paused"

local state = {
  ---@type obsidian.sync.StatusKind
  kind = "paused",
}

vim.g.obsidian_sync_status_icon = ""
vim.g.obsidian_sync_status = ""

local function color()
  local hl = group[state.kind]
  return hl or "DiagnosticInfo"
end

---@param kind obsidian.sync.StatusKind
local function set(kind)
  if kind == "syncing" and state.kind == "paused" then -- HACK:
    return
  end

  state.kind = kind
  local icon = (kind and sync_icons[kind]) or ""
  local hl = color()

  vim.g.obsidian_sync_status_icon = icon
  vim.g.obsidian_sync_status = icon ~= "" and string.format(" %%#%s# %s %%*", hl, icon) or ""
end

return {
  set = set,
  color = color,
}
