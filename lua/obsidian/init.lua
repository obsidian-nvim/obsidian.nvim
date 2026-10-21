local log = require "obsidian.log"

local obsidian = {}

obsidian.api = require "obsidian.api"
obsidian.actions = require "obsidian.actions"
obsidian.code_action = require "obsidian.lsp.handlers._code_action"
obsidian.async = require "obsidian.async"
obsidian.Client = require "obsidian.client"
obsidian.commands = require "obsidian.commands"
obsidian.config = require "obsidian.config"
obsidian.date = require "obsidian.date"
obsidian.link = require "obsidian.link"
obsidian.log = log
obsidian.img_paste = require "obsidian.img_paste"
obsidian.Note = require "obsidian.note"
obsidian.Path = require "obsidian.path"
obsidian.Picker = require "obsidian.picker"
obsidian.search = require "obsidian.search"
obsidian.templates = require "obsidian.templates"
obsidian.ui = require "obsidian.ui"
obsidian.uri = require "obsidian.uri"
obsidian.util = require "obsidian.util"
obsidian.VERSION = require "obsidian.version"
obsidian.Workspace = require "obsidian.workspace"
obsidian.yaml = require "obsidian.yaml"

---@type obsidian.Client |?
obsidian._client = nil

--- TODO: remove in 4.0.0

--- Get the current obsidian client.
---@return obsidian.Client
obsidian.get_client = function()
  ---@type obsidian.Client?
  local client = rawget(obsidian, "_client")
  if client == nil then
    error "Obsidian client has not been set! Did you forget to call 'setup()'?"
  end
  return client
end

obsidian.register_command = require("obsidian.commands").register

---Set up or replace the Obsidian configuration.
---Repeated calls replace the previous options and registered workspaces.
---
---@param user_opts obsidian.config
---
---@return obsidian.Client?
obsidian.setup = function(user_opts)
  user_opts = user_opts or {}
  local normalized, opts = pcall(obsidian.config.normalize, user_opts)
  if Obsidian and Obsidian.opts then
    if not normalized then
      log.err("%s\n\nKeeping the previous obsidian.nvim configuration.", opts)
      return
    end
    require("obsidian.sync").shutdown()
    require("obsidian.autocmds").reset()
    require("obsidian.cache").shutdown()
    require("obsidian.cache.volatile").reset_workspace { vaults = true }
    obsidian.ui.shutdown()
  end
  ---@class obsidian.state
  ---@field picker     obsidian.Picker          Picker to use.
  ---@field workspace  obsidian.Workspace       Current workspace.
  ---@field workspaces obsidian.Workspace[]     All workspaces.
  ---@field dir        obsidian.Path            Root of the vault for the current workspace.
  ---@field buf_dir    obsidian.Path |?         Parent directory of the current buffer.
  ---@field opts          obsidian.config.Internal Current options.
  ---@field _opts         obsidian.config.Internal Normalized user options.
  ---@field _user_opts    obsidian.config Raw options passed to setup.
  ---@field _setup_called boolean Whether setup has been called.
  ---@field _config_error string|? Configuration error from the latest setup call.
  ---@diagnostic disable-next-line: global-in-non-module
  Obsidian = setmetatable({}, {
    __index = function(_, key)
      if key == "picker" then
        return obsidian.Picker
      end
    end,
  })

  Obsidian._setup_called = true
  Obsidian._user_opts = user_opts
  if not normalized then
    Obsidian._config_error = tostring(opts)
    log.err("%s\n\nobsidian.nvim did not finish setup.", Obsidian._config_error)
    return
  end
  ---@cast opts obsidian.config.Internal

  Obsidian._opts = opts

  obsidian.Workspace.setup(opts.workspaces)

  local docs_dir = obsidian.api.docs_dir()

  if docs_dir then
    Obsidian.workspaces[#Obsidian.workspaces + 1] = obsidian.Workspace.new {
      path = docs_dir,
      root = docs_dir,
      strict = true,
      name = ".obsidian.wiki",
      -- TODO: override no daily and template dir once those two module get `.enabled` option
    }
  end

  local client = obsidian.Client.new() -- TODO: remove in 4.0.0

  log.set_level(Obsidian.opts.log_level)

  obsidian.Picker.get(Obsidian.opts.picker.name)

  if opts.legacy_commands then
    obsidian.commands.install_legacy()
  end

  -- Set global client.
  obsidian._client = client

  -- experimental values don't want to expose, override in post_setup
  vim.g.obsidian_sync_on_write_debounce_ms = 2000

  obsidian.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup)
  require("obsidian.autocmds").setup()

  return client
end

return obsidian
