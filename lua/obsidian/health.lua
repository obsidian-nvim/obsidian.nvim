local M = {}
local VERSION = require "obsidian.version"
local api = require "obsidian.api"
local sync_client = require "obsidian.sync.client"

local error = vim.health.error
local warn = vim.health.warn
local ok = vim.health.ok

local function error_f(...)
  local t = { ... }
  local format = table.remove(t, 1)
  local str = #t == 0 and tostring(format) or string.format(tostring(format), unpack(t))
  return error(str)
end

local function warn_f(...)
  local t = { ... }
  local format = table.remove(t, 1)
  local str = #t == 0 and tostring(format) or string.format(tostring(format), unpack(t))
  return warn(str)
end

local function ok_f(...)
  local t = { ... }
  local format = table.remove(t, 1)
  local str = #t == 0 and tostring(format) or string.format(tostring(format), unpack(t))
  return ok(str)
end

---@private
---@param name string
local function start(name)
  vim.health.start(string.format("[%s]", name))
end

---@param plugin string
---@param optional boolean
---@return boolean
local function has_plugin(plugin, optional)
  local plugin_info = api.get_plugin_info(plugin)
  if plugin_info then
    ok_f("%s: %s", plugin, plugin_info.commit or "unknown")
    return true
  else
    if not optional then
      error(" " .. plugin .. " not installed")
    end
    return false
  end
end

---@class obsidian.DependencyInfo
---@field path string
---@field version string

---@param name string
---@return obsidian.DependencyInfo
local function get_exe_info(name)
  local path = vim.fn.exepath(name)
  local out = vim.trim(vim.fn.system { name, "--version" })
  local version = vim.version.parse(out)
  local version_string = version and ("%d.%d.%d"):format(version.major, version.minor, version.patch)
    or "unknown version"
  return { path = path, version = version_string, out = out }
end

local function has_executable(name, optional)
  if vim.fn.executable(name) == 1 then
    local exe = get_exe_info(name)
    ok_f("%s: %s (%s)", name, exe.version, exe.path)
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
    warn("It is recommended to install at least one of " .. vim.inspect(plugins))
  end
end

---@param executables string[]
---@return string
local function executable_list(executables)
  return "`" .. table.concat(executables, "`, `") .. "`"
end

---@param executables string[]
---@param opts? { feature?: string, hint?: string }
local function has_one_of_executable(executables, opts)
  opts = opts or {}
  local found
  local checked = {}
  for _, name in ipairs(executables) do
    if name and name ~= "" and not checked[name] then
      checked[name] = true
      if has_executable(name, true) then
        found = true
      end
    end
  end
  if found then
    return
  end

  local msg = string.format("%s requires one of: %s", opts.feature or "optional feature", executable_list(executables))
  if opts.hint then
    msg = msg .. ". " .. opts.hint
  end
  warn(msg)
end

---@param minimum string
---@param recommended string
local function neovim(minimum, recommended)
  ---@diagnostic disable-next-line: call-non-callable
  local version = tostring(vim.version())
  if vim.fn.has("nvim-" .. minimum) == 0 then
    error_f("neovim < %s (%s)", minimum, version)
  elseif vim.fn.has("nvim-" .. recommended) == 0 then
    warn_f("neovim < %s some features will not work (%s)", recommended, version)
  else
    ok_f("neovim >= %s (%s)", recommended, version)
  end
end

function M.check()
  local os = api.get_os()
  neovim("0.11", "0.12")
  start "Version"
  local plugin_info = api.get_plugin_info "obsidian.nvim"
  ok_f("obsidian.nvim v%s (%s)", VERSION, plugin_info and plugin_info.commit or "unknown commit")

  start "Environment"
  ok_f("operating system: %s", os)

  start "Config"
  ok_f("dir: %s", Obsidian.dir)

  start "Pickers"

  has_one_of {
    "telescope.nvim",
    "fzf-lua",
    "mini.nvim",
    "mini.pick",
    "snacks.nvim",
  }

  start "Dependencies"
  has_executable("rg", false)

  start "Audio recorder"
  has_one_of_executable({
    "rec",
    "sox",
    "arecord",
  }, {
    feature = "audio recorder",
    hint = "Install SoX (provides `rec`/`sox`) or ALSA `arecord` to record audio notes.",
  })

  start "Image paste"
  if os == api.OSType.Linux or os == api.OSType.FreeBSD then
    has_one_of_executable({
      "xclip",
      "wl-paste",
    }, {
      feature = ":Obsidian paste_img",
      hint = "Use `xclip` on X11 or `wl-clipboard` (provides `wl-paste`) on Wayland.",
    })
  elseif os == api.OSType.Darwin then
    has_one_of_executable({ "pngpaste" }, {
      feature = ":Obsidian paste_img",
      hint = "Install `pngpaste` to paste clipboard images.",
    })
  elseif os == api.OSType.Windows or os == api.OSType.Wsl then
    ok_f ":Obsidian paste_img uses PowerShell clipboard support"
  else
    warn_f(":Obsidian paste_img is not implemented for %s", os)
  end

  if os == api.OSType.Wsl then
    start "Open"
    has_one_of_executable({ "wsl-open" }, {
      feature = ":Obsidian open on WSL",
      hint = "Install `wsl-open` to open notes in the Obsidian app from WSL.",
    })
  end

  start "Sync"
  local sync_opts = Obsidian.opts.sync or {}
  local backend = sync_opts.backend or "obsidian"
  ok_f("backend: %s", backend)
  if not sync_opts.enabled then
    ok "disabled; obsidian-headless CLI is only needed when sync is enabled"
  elseif backend == "obsidian" then
    local sync_executables = { "ob" }
    if sync_client.cmd and sync_client.cmd ~= "ob" then
      table.insert(sync_executables, sync_client.cmd)
    end
    has_one_of_executable(sync_executables, {
      feature = "sync (:Obsidian sync)",
      hint = "Install `obsidian-headless` (`ob`) or run the local CLI install prompt.",
    })
  else
    ok_f("custom backend: %s", backend)
  end

  start "Compatibility"
  local warning = require("obsidian.lsp.util").check_completion_availability()
  if warning then
    warn_f(warning)
  end
end

return M
