local M = {}
local VERSION = require "obsidian.version"
local api = require "obsidian.api"

local error = vim.health.error
local warn = vim.health.warn
local ok = vim.health.ok

local function info(...)
  local t = { ... }
  local format = table.remove(t, 1)
  local str = #t == 0 and format or string.format(format, unpack(t))
  return ok(str)
end

---@private
---@param name string
local function start(name)
  vim.health.start(string.format("obsidian.nvim [%s]", name))
end

---@param plugin string
---@param optional boolean
---@return boolean
local function has_plugin(plugin, optional)
  local plugin_info = api.get_plugin_info(plugin)
  if plugin_info then
    info("%s: %s", plugin, plugin_info.commit or "unknown")
    return true
  else
    if not optional then
      vim.health.error(" " .. plugin .. " not installed")
    end
    return false
  end
end

local function has_executable(name, optional)
  if vim.fn.executable(name) == 1 then
    local version = api.get_external_dependency_info(name)
    if version then
      info("%s: %s", name, version)
    else
      info("%s: found", name)
    end
    return true
  else
    if not optional then
      error(string.format("%s not found", name))
    end
    return false
  end
end

---@param plugins string[]
local function has_one_of(plugins)
  local found
  for _, name in ipairs(plugins) do
    if has_plugin(name, true) then
      found = true
    end
  end
  if not found then
    vim.health.warn("It is recommended to install at least one of " .. vim.inspect(plugins))
  end
end

---@param plugins string[]
local function has_one_of_executable(plugins)
  local found
  for _, name in ipairs(plugins) do
    if has_executable(name, true) then
      found = true
    end
  end
  if not found then
    vim.health.warn("It is recommended to install at least one of " .. vim.inspect(plugins))
  end
end

---@param minimum string
---@param recommended string
local function neovim(minimum, recommended)
  if vim.fn.has("nvim-" .. minimum) == 0 then
    error("neovim < " .. minimum)
  elseif vim.fn.has("nvim-" .. recommended) == 0 then
    warn("neovim < " .. recommended .. " some features will not work")
  else
    ok("neovim >= " .. recommended)
  end
end

function M.check()
  local os = api.get_os()
  neovim("0.10", "0.11")
  start "Version"
  info("obsidian.nvim v%s (%s)", VERSION, api.get_plugin_info("obsidian.nvim").commit)

  start "Environment"
  info("operating system: %s", os)

  start "Config"
  info("dir: %s", require("obsidian").get_client().dir)

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
  has_executable("rg", false)
  has_plugin("plenary.nvim", false)

  if os == api.OSType.Wsl then
    has_executable("wsl-open", true)
  elseif os == api.OSType.Linux then
    has_one_of_executable {
      "xclip",
      "wl-paste",
    }
  elseif os == api.OSType.Darwin then
    has_executable("pngpaste", true)
  end
end

return M
