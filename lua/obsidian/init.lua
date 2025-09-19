local log = require "obsidian.log"

local obsidian = {}

obsidian.abc = require "obsidian.abc"
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
obsidian.pickers = require "obsidian.pickers"
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
  _G.Obsidian = {}

  local opts = obsidian.config.normalize(user_opts)

  local client = obsidian.Client.new() -- TODO: remove in 4.0.0
  local workspaces = {}

  for _, spec in ipairs(opts.workspaces) do
    local ws = obsidian.Workspace.new(spec)
    if ws then
      table.insert(workspaces, ws)
    end
  end

  if vim.tbl_isempty(workspaces) then
    error "At least one workspace is required!\nPlease specify a valid workspace"
  end

  Obsidian.workspaces = workspaces

  Obsidian._opts = opts

  obsidian.Workspace.set(Obsidian.workspaces[1])

  log.set_level(Obsidian.opts.log_level)

  obsidian.commands.install()

  -- Setup UI add-ons.
  local has_no_renderer = not (
    obsidian.api.get_plugin_info "render-markdown.nvim" or obsidian.api.get_plugin_info "markview.nvim"
  )
  if has_no_renderer and Obsidian.opts.ui.enable then
    require("obsidian.ui").setup(Obsidian.workspace, Obsidian.opts.ui)
  end

  Obsidian.picker = require("obsidian.pickers").get(Obsidian.opts.picker.name)

  if opts.legacy_commands then
    obsidian.commands.install_legacy(client)
  end

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

  local group = vim.api.nvim_create_augroup("obsidian_setup", { clear = true })

  -- wrapper for creating autocmd events
  ---@param pattern string
  ---@param buf integer
  local function exec_autocmds(pattern, buf)
    vim.api.nvim_exec_autocmds("User", {
      pattern = pattern,
      data = {
        note = require("obsidian.note").from_buffer(buf),
      },
    })
  end

  -- find workspaces of a path
  ---@param path string
  ---@return obsidian.Workspace
  local function find_workspace(path)
    return vim.iter(Obsidian.workspaces):find(function(ws)
      return obsidian.api.path_is_note(path, ws)
    end)
  end

  -- Complete setup and update workspace (if needed) when entering a markdown buffer.
  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      -- Set the current directory of the buffer.
      local buf_dir = vim.fs.dirname(ev.match)
      if buf_dir then
        Obsidian.buf_dir = obsidian.Path.new(buf_dir)
      end

      -- Check if we're in *any* workspace.
      local workspace = find_workspace(ev.match)
      if not workspace then
        return
      end

      vim.b[ev.buf].obsidian_buffer = true

      if opts.comment.enabled then
        vim.o.commentstring = "%%%s%%"
      end

      -- Register keymap.
      vim.keymap.set(
        "n",
        "<CR>",
        obsidian.api.smart_action,
        { expr = true, buffer = true, desc = "Obsidian Smart Action" }
      )

      vim.keymap.set("n", "]o", function()
        obsidian.api.nav_link "next"
      end, { buffer = true, desc = "Obsidian Next Link" })

      vim.keymap.set("n", "[o", function()
        obsidian.api.nav_link "prev"
      end, { buffer = true, desc = "Obsidian Previous Link" })

      -- Inject completion sources, providers to their plugin configurations
      if opts.completion.nvim_cmp then
        require("obsidian.completion.plugin_initializers.nvim_cmp").inject_sources(opts)
      elseif opts.completion.blink then
        require("obsidian.completion.plugin_initializers.blink").inject_sources(opts)
      end

      require("obsidian.lsp").start(ev.buf)

      -- Run enter-note callback.
      local note = obsidian.Note.from_buffer(ev.buf)
      obsidian.util.fire_callback("enter_note", Obsidian.opts.callbacks.enter_note, note)

      exec_autocmds("ObsidianNoteEnter", ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      -- Run leave-note callback.
      local note = obsidian.Note.from_buffer(ev.buf)
      obsidian.util.fire_callback("leave_note", Obsidian.opts.callbacks.leave_note, note)

      exec_autocmds("ObsidianNoteLeave", ev.buf)
    end,
  })

  -- Add/update frontmatter for notes before writing.
  vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      -- Initialize note.
      local bufnr = ev.buf
      local note = obsidian.Note.from_buffer(bufnr)

      -- Run pre-write-note callback.
      obsidian.util.fire_callback("pre_write_note", Obsidian.opts.callbacks.pre_write_note, note)

      exec_autocmds("ObsidianNoteWritePre", ev.buf)

      -- Update buffer with new frontmatter.
      note:update_frontmatter(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      -- Check if current buffer is actually a note within the workspace.
      if not obsidian.api.path_is_note(ev.match) then
        return
      end

      exec_autocmds("ObsidianNoteWritePost", ev.buf)
    end,
  })

  -- Set global client.
  obsidian._client = client

  obsidian.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup)

  return client
end

return obsidian
