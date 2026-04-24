local log = require "obsidian.log"

local M = {}

---@param ws obsidian.Workspace
local function ws_label(ws)
  return string.format("%s (%s)", ws.name, tostring(ws.root))
end

---@param backend obsidian.sync.Backend
---@return fun(ws: obsidian.Workspace): string
local function get_formatter(backend)
  if backend.ws_formatter then
    return backend.ws_formatter()
  end
  return ws_label
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

  local format_item = get_formatter(backend)

  vim.ui.select(workspaces, {
    prompt = "Select workspace to set up sync for",
    format_item = format_item,
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

  local format_item = get_formatter(backend)

  vim.ui.select(linked, {
    prompt = "Select workspace to unlink",
    format_item = format_item,
  }, function(ws)
    if ws then
      backend.disconnect(ws)
    end
  end)
end

return M
