local log = require "obsidian.log"

local obsidian = {}

obsidian.api = require "obsidian.api"
obsidian.async = require "obsidian.async"
obsidian.Client = require "obsidian.client"
obsidian.commands = require "obsidian.commands"
obsidian.completion = require "obsidian.completion"
obsidian.config = require "obsidian.config"
obsidian.log = require "obsidian.log"
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
  if obsidian._client == nil then
    error "Obsidian client has not been set! Did you forget to call 'setup()'?"
  else
    return obsidian._client
  end
end

obsidian.register_command = require("obsidian.commands").register

--- Setup a new Obsidian client. This should only be called once from an Nvim session.
---
---@param user_opts obsidian.config
---
---@return obsidian.Client
obsidian.setup = function(user_opts)
  ---@class obsidian.state
  ---@field picker obsidian.Picker Picker to use.
  ---@field workspace obsidian.Workspace Current workspace.
  ---@field workspaces obsidian.Workspace[] All workspaces.
  ---@field dir obsidian.Path Root of the vault for the current workspace.
  ---@field buf_dir obsidian.Path|? Parent directory of the current buffer.
  ---@field opts obsidian.config.Internal Current options.
  ---@field _opts obsidian.config.Internal User input options.
  Obsidian = {}

  local opts = obsidian.config.normalize(user_opts)

  Obsidian._opts = opts

  obsidian.Workspace.setup(opts.workspaces)

  local client = obsidian.Client.new() -- TODO: remove in 4.0.0

  log.set_level(Obsidian.opts.log_level)

  obsidian.commands.install()

  -- Setup UI add-ons.
  local has_no_renderer = not (
    obsidian.api.get_plugin_info "render-markdown.nvim" or obsidian.api.get_plugin_info "markview.nvim"
  )
  if has_no_renderer and Obsidian.opts.ui.enable then
    require("obsidian.ui").setup(Obsidian.workspace, Obsidian.opts.ui)
  end

  Obsidian.picker = obsidian.Picker.get()

  if opts.legacy_commands then
    obsidian.commands.install_legacy()
  end

  --- TODO: remove in 4.0.0
  if opts.statusline.enabled then
    require("obsidian.statusline").start()
  end

  if opts.footer.enabled then
    require("obsidian.footer").start()
  end

  -- Register completion sources, providers
  if opts.completion.nvim_cmp then
    require("obsidian.completion.plugin_initializers.nvim_cmp").register_sources()
  elseif opts.completion.blink then
    require("obsidian.completion.plugin_initializers.blink").register_providers()
  end

  -- Register autocmds for keymaps, options and custom callbacks
  require "obsidian.autocmds"

  -- Set global client.
  obsidian._client = client

  obsidian.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup)

  return client
end

return obsidian
