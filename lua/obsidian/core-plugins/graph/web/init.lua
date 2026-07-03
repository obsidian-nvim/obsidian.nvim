-- HTML page renderer for the graph view.
-- Keep web UI source in plain HTML/CSS/JS files for easier editing.

local M = {}
local util = require "obsidian.util"

local ASSET_RUNTIME_DIR = "lua/obsidian/core-plugins/graph/web"

---@param name string
---@return string
local function asset_path(name)
  local rel = ASSET_RUNTIME_DIR .. "/" .. name
  local matches = vim.api.nvim_get_runtime_file(rel, false)
  if matches[1] then
    return matches[1]
  end

  -- Fallback for tests or direct package.path loading where this plugin root is
  -- not on 'runtimepath'.
  local source = assert(debug.getinfo(1, "S")).source
  if source:sub(1, 1) == "@" then
    local path = vim.fn.fnamemodify(source:sub(2), ":p:h") .. "/" .. name
    if vim.uv.fs_stat(path) then
      return path
    end
  end

  error("obsidian graph web asset not found: " .. rel)
end

---@param name string
---@return string
local function read_asset(name)
  return util.read_file(asset_path(name))
end

---@param opts { token: string? }?
---@return string
function M.render(opts)
  local token = opts and opts.token or ""
  local html = read_asset "index.html"
  local result = html
    :gsub("__OBSIDIAN_GRAPH_CSS__", function()
      return read_asset "graph.css"
    end)
    :gsub("__OBSIDIAN_GRAPH_JS__", function()
      return read_asset "graph.js"
    end)
    :gsub("__OBSIDIAN_GRAPH_TOKEN__", function()
      return vim.json.encode(token)
    end)
  return result
end

return M
