---@class render.md.Health
local M = {}
local util = require "obsidian.util"
local VERSION = require "obsidian.version"

local info = function(...)
  local t = { ... }
  local format = table.remove(t, 1)
  local str = #t == 0 and format or string.format(format, unpack(t))
  return vim.health.ok(str)
end

---@private
---@param name string
local function start(name)
  vim.health.start(string.format("obsidian.nvim [%s]", name))
end

---@param plugin string
---@return boolean
local function check_plugin(plugin)
  local plugin_info = util.get_plugin_info(plugin)
  if plugin_info then
    info("  ✓ %s: %s", plugin, plugin_info.commit or "unknown")
    return true
  end
  return false
end

---@param plugins string[]
local function has_one_of(plugins)
  local found
  for _, plugin in ipairs(plugins) do
    if check_plugin(plugin) then
      found = true
    end
  end
  if not found then
    vim.health.warning("Need at least one of " .. vim.inspect(plugins))
  end
end

local Path = require "obsidian.path"

---@param minimum string
---@param recommended string
local function neovim(minimum, recommended)
  if vim.fn.has("nvim-" .. minimum) == 0 then
    vim.health.error("neovim < " .. minimum)
  elseif vim.fn.has("nvim-" .. recommended) == 0 then
    vim.health.warn("neovim < " .. recommended .. " some features will not work")
  else
    vim.health.ok("neovim >= " .. recommended)
  end
end

function M.check()
  neovim("0.8", "0.11")
  start "Version"
  local ob_info = util.get_plugin_info() or {}
  info("Obsidian.nvim v%s (%s)", VERSION, ob_info.commit or "unknown commit")

  start "Status"
  -- ok("  • buffer directory: %s", client.buf_dir)
  info("  • working directory: %s", Path.cwd())

  start "Pickers"

  has_one_of {
    "telescope.nvim",
    "fzf-lua",
    "mini.nvim",
    "mini.pick",
    "snacks.nvim",
  }

  start "Completion"

  has_one_of {
    "nvim-cmp",
    "blink.cmp",
  }

  start "Dependencies"
  info("  ✓ rg: %s", util.get_external_dependency_info "rg" or "not found")
  info("  ✓ %s: %s", "plenary.nvim", util.get_plugin_info("plenary.nvim").commit or "unknown")

  start "Environment"
  info("  • operating system: %s", util.get_os())

  -- start "Config:"
  -- ok("  • notes_subdir: %s", client.opts.notes_subdir)
end

return M
