local log = require "obsidian.log"

local obsidian = {}

obsidian.api = require "obsidian.api"
obsidian.actions = require "obsidian.actions"
obsidian.code_action = require "obsidian.lsp.handlers._code_action"
obsidian.async = require "obsidian.async"
obsidian.Client = require "obsidian.client"
obsidian.commands = require "obsidian.commands"
obsidian.config = require "obsidian.config"
obsidian.log = log
obsidian.img_paste = require "obsidian.img_paste"
obsidian.Note = require "obsidian.note"
obsidian.Path = require "obsidian.path"
obsidian.Picker = require "obsidian.picker"
obsidian.search = require "obsidian.search"
obsidian.templates = require "obsidian.templates"
obsidian.ui = require "obsidian.ui"
obsidian.util = require "obsidian.util"
obsidian.VERSION = require "obsidian.version"
obsidian.Workspace = require "obsidian.workspace"
obsidian.yaml = require "obsidian.yaml"

---@type obsidian.Client|?
obsidian._client = nil

--- TODO: remove in 4.0.0

---Get the current obsidian client.
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

--- Setup a new Obsidian client. This should only be called once from an Nvim session.
---
---@param user_opts obsidian.config
---
---@return obsidian.Client
obsidian.setup = function(user_opts)
  ---@class obsidian.state
  ---@field picker obsidian.Picker Deprecated. Use `require "obsidian.picker"`.
  ---@field workspace obsidian.Workspace Current workspace.
  ---@field workspaces obsidian.Workspace[] All workspaces.
  ---@field dir obsidian.Path Root of the vault for the current workspace.
  ---@field buf_dir obsidian.Path|? Parent directory of the current buffer.
  ---@field opts obsidian.config.Internal Current options.
  ---@field _opts obsidian.config.Internal User input options.
  ---@diagnostic disable-next-line: global-in-non-module
  Obsidian = setmetatable({}, {
    __index = function(_, key)
      if key == "picker" then
        return obsidian.Picker
      end
    end,
  })

  local opts = obsidian.config.normalize(user_opts)

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

  -- Register autocmds for keymaps, options and custom callbacks
  require "obsidian.autocmds"

  -- Setup the cache (no-op when disabled).
  require("obsidian.cache").setup(Obsidian.opts.cache)

  -- Set global client.
  obsidian._client = client

  -- experimental values don't want to expose, override in post_setup
  vim.g.obsidian_sync_on_write_debounce_ms = 2000

  obsidian.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup)

  return client
end

return obsidian
