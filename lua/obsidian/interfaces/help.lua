local Path = require "obsidian.path"
local runtime = require "obsidian.runtime"
local log = require "obsidian.log"
local picker = require "obsidian.picker"

local M = {}

--- TODO: will not work if plugin is managed by nix
---
---@return obsidian.Path|?
M.get_dir = function()
  local info = runtime.get_plugin_info "obsidian.nvim"
  if not info then
    return
  end

  ---@type obsidian.Path
  local dir = Path.new(info.path) / "docs"
  return dir
end

M.pick = function(query)
  query = query or ""
  local dir = M.get_dir()

  if not dir then
    log.err "Failed to locate docs dir"
    return
  end

  if query ~= "" then
    local matches = {}

    local function check_path(p)
      if p:is_file() then
        table.insert(matches, p)
      end
    end

    check_path(dir / (query .. ".md"))
    check_path(dir / query)

    if #matches == 1 then
      vim.cmd("edit " .. tostring(matches[1]))
      return
    end
  end

  picker.find_notes {
    prompt_title = "Obsidian Help",
    dir = dir,
    query = query,
  }
end

M.grep = function(query)
  local dir = M.get_dir()
  if not dir then
    log.err "Failed to locate docs dir"
    return
  end

  picker.grep_notes {
    prompt_title = "Quick Switch",
    dir = dir,
    query = query,
  }
end

return M
