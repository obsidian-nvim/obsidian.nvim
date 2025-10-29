local log = require "obsidian.log"

local M = {}

M.abc = require "obsidian.abc"
M.api = require "obsidian.api"
M.async = require "obsidian.async"
M.Client = require "obsidian.client"
M.commands = require "obsidian.commands"
M.completion = require "obsidian.completion"
M.config = require "obsidian.config"
M.log = require "obsidian.log"
M.img_paste = require "obsidian.img_paste"
M.Note = require "obsidian.note"
M.Path = require "obsidian.path"
M.Picker = require "obsidian.picker"
M.search = require "obsidian.search"
M.templates = require "obsidian.templates"
M.ui = require "obsidian.ui"
M.util = require "obsidian.util"
M.VERSION = require "obsidian.version"
M.Workspace = require "obsidian.workspace"
M.yaml = require "obsidian.yaml"

---@type obsidian.Client|?
M._client = nil

--- TODO: remove in 4.0.0

---Get the current obsidian client.
---@return obsidian.Client
M.get_client = function()
  if M._client == nil then
    error "Obsidian client has not been set! Did you forget to call 'setup()'?"
  else
    return M._client
  end
end

M.register_command = require("obsidian.commands").register

--- Setup a new Obsidian client. This should only be called once from an Nvim session.
---
---@param user_opts obsidian.config
---
---@return obsidian.Client
M.setup = function(user_opts)
  ---@class obsidian.state
  ---@field picker obsidian.Picker Picker to use.
  ---@field workspace obsidian.Workspace Current workspace.
  ---@field workspaces obsidian.Workspace[] All workspaces.
  ---@field dir obsidian.Path Root of the vault for the current workspace.
  ---@field buf_dir obsidian.Path|? Parent directory of the current buffer.
  ---@field opts obsidian.config.Internal Current options.
  ---@field _opts obsidian.config.Internal User input options.
  Obsidian = {}

  local opts = M.config.normalize(user_opts)

  Obsidian._opts = opts

  M.Workspace.setup(opts.workspaces)

  local client = M.Client.new() -- TODO: remove in 4.0.0

  log.set_level(Obsidian.opts.log_level)

  M.commands.install()

  -- Setup UI add-ons.
  local has_no_renderer = not (M.api.get_plugin_info "render-markdown.nvim" or M.api.get_plugin_info "markview.nvim")
  if has_no_renderer and Obsidian.opts.ui.enable then
    require("obsidian.ui").setup(Obsidian.workspace, Obsidian.opts.ui)
  end

  Obsidian.picker = M.Picker.get()

  if opts.legacy_commands then
    M.commands.install_legacy()
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
    require("obsidian.completion.plugin_initializers.nvim_cmp").register_sources(opts)
  elseif opts.completion.blink then
    require("obsidian.completion.plugin_initializers.blink").register_providers(opts)
  end

  -- Register autocmds for keymaps, options and custom callbacks
  require "obsidian.autocmds"

  -- Set global client.
  M._client = client

  M.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup)

  return client
end

return M
