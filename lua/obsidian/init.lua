local log = require "obsidian.log"

local module_lookups = {
  abc = "obsidian.abc",
  api = "obsidian.api",
  async = "obsidian.async",
  Client = "obsidian.client",
  commands = "obsidian.commands",
  completion = "obsidian.completion",
  config = "obsidian.config",
  log = "obsidian.log",
  img_paste = "obsidian.img_paste",
  Note = "obsidian.note",
  Path = "obsidian.path",
  pickers = "obsidian.pickers",
  search = "obsidian.search",
  templates = "obsidian.templates",
  ui = "obsidian.ui",
  util = "obsidian.util",
  VERSION = "obsidian.version",
  Workspace = "obsidian.workspace",
  yaml = "obsidian.yaml",
}

local obsidian = setmetatable({}, {
  __index = function(t, k)
    local require_path = module_lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

---@type obsidian.Client|?
obsidian._client = nil

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
---@param opts obsidian.config.ClientOpts | table<string, any>
---
---@return obsidian.Client
obsidian.setup = function(opts)
  ---@class obsidian.state
  ---@field picker obsidian.Picker Picker to use.
  ---@field workspace obsidian.Workspace Current workspace.
  ---@field workspaces obsidian.Workspace[] All workspaces.
  ---@field dir obsidian.Path Root of the vault for the current workspace.
  ---@field buf_dir obsidian.Path|? Parent directory of the current buffer.
  ---@field opts obsidian.config.ClientOpts Current options.
  ---@field _opts obsidian.config.ClientOpts User input options.
  _G.Obsidian = {}

  opts = obsidian.config.normalize(opts)

  local client = obsidian.Client.new(opts)

  Obsidian._opts = opts

  obsidian.Workspace.set(Obsidian.workspaces[1])

  log.set_level(Obsidian.opts.log_level)

  obsidian.commands.install(client)

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
      local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, Obsidian.opts.workspaces)
      if not workspace then
        return
      end

      if opts.comment.enabled then
        vim.o.commentstring = "%%%s%%"
      end

      -- Switch to the workspace and complete the workspace setup.
      if not Obsidian.workspace.locked and workspace ~= Obsidian.workspace then
        log.debug("Switching to workspace '%s' @ '%s'", workspace.name, workspace.path)
        obsidian.Workspace.set(workspace)
        require("obsidian.ui").update(ev.buf)
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
      obsidian.util.fire_callback("enter_note", Obsidian.opts.callbacks.enter_note, client, note)

      exec_autocmds("ObsidianNoteEnter", ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufLeave" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      -- Check if we're in *any* workspace.
      local workspace = obsidian.Workspace.get_workspace_for_dir(vim.fs.dirname(ev.match), Obsidian.opts.workspaces)
      if not workspace then
        return
      end

      -- Check if current buffer is actually a note within the workspace.
      if not obsidian.api.path_is_note(ev.match) then
        return
      end

      -- Run leave-note callback.
      local note = obsidian.Note.from_buffer(ev.buf)
      obsidian.util.fire_callback("leave_note", Obsidian.opts.callbacks.leave_note, client, note)

      exec_autocmds("ObsidianNoteLeave", ev.buf)
    end,
  })

  -- Add/update frontmatter for notes before writing.
  vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local buf_dir = vim.fs.dirname(ev.match)

      -- Check if we're in a workspace.
      local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, Obsidian.opts.workspaces)
      if not workspace then
        return
      end

      -- Check if current buffer is actually a note within the workspace.
      if not obsidian.api.path_is_note(ev.match) then
        return
      end

      -- Initialize note.
      local bufnr = ev.buf
      local note = obsidian.Note.from_buffer(bufnr)

      -- Run pre-write-note callback.
      obsidian.util.fire_callback("pre_write_note", Obsidian.opts.callbacks.pre_write_note, client, note)

      exec_autocmds("ObsidianNoteWritePre", ev.buf)

      -- Update buffer with new frontmatter.
      note:update_frontmatter(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    group = group,
    pattern = "*.md",
    callback = function(ev)
      local buf_dir = vim.fs.dirname(ev.match)

      -- Check if we're in a workspace.
      local workspace = obsidian.Workspace.get_workspace_for_dir(buf_dir, Obsidian.opts.workspaces)
      if not workspace then
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

  obsidian.util.fire_callback("post_setup", Obsidian.opts.callbacks.post_setup, client)

  return client
end

return obsidian
