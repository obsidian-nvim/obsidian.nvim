local api = require "obsidian.api"
local util = require "obsidian.util"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local group = vim.api.nvim_create_augroup("obsidian_setup", { clear = true })

-- wrapper for creating autocmd events
---@param pattern string
local function exec_autocmds(pattern)
  vim.api.nvim_exec_autocmds("User", { pattern = pattern })
end

local function create_autocmd(events, buffer, callback)
  vim.api.nvim_create_autocmd(events, {
    group = group,
    buffer = buffer,
    callback = callback,
  })
end

-- Complete setup and update workspace (if needed) when entering a markdown buffer.
local function bufenter_callback(ev)
  -- Set the current directory of the buffer.
  local buf_dir = vim.fs.dirname(ev.file)
  if buf_dir then
    Obsidian.buf_dir = Path.new(buf_dir)
  end

  -- Check if we're in *any* workspace.
  local workspace = api.find_workspace(ev.file)
  if not workspace then
    return
  end

  local opts = Obsidian.opts

  vim.b[ev.buf].obsidian_buffer = true

  if opts.comment.enabled then
    vim.o.commentstring = "%%%s%%"
  end

  -- Register keymap.
  vim.keymap.set("n", "<CR>", api.smart_action, { expr = true, buffer = true, desc = "Obsidian Smart Action" })

  vim.keymap.set("n", "]o", function()
    api.nav_link "next"
  end, { buffer = true, desc = "Obsidian Next Link" })

  vim.keymap.set("n", "[o", function()
    api.nav_link "prev"
  end, { buffer = true, desc = "Obsidian Previous Link" })

  -- Inject completion sources, providers to their plugin configurations
  if opts.completion.nvim_cmp then
    require("obsidian.completion.plugin_initializers.nvim_cmp").inject_sources()
  elseif opts.completion.blink then
    require("obsidian.completion.plugin_initializers.blink").inject_sources()
  end

  require("obsidian.lsp").start(ev.buf)

  exec_autocmds "ObsidianNoteEnter"
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  -- <<<<<<< HEAD
  pattern = { "markdown", "quarto" },
  callback = function(args)
    create_autocmd("BufEnter", args.buf, bufenter_callback)
    create_autocmd("BufLeave", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      exec_autocmds "ObsidianNoteLeave"
    end)
    create_autocmd("BufWritePre", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      exec_autocmds "ObsidianNoteWritePre"
      local note = Note.from_buffer(ev.buf)
      note:update_frontmatter(ev.buf) -- Update buffer with new frontmatter.
    end)
    create_autocmd("BufWritePost", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      exec_autocmds "ObsidianNoteWritePost"
    end)
    -- =======
    --   pattern = "*.md",
    --   callback = function(ev)
    --     -- Set the current directory of the buffer.
    --     local buf_dir = vim.fs.dirname(ev.match)
    --
    --     local is_help = tostring(api.help_wiki_dir()) == buf_dir
    --
    --     -- Check if we're in *any* workspace.
    --     local workspace = find_workspace(ev.match)
    --     if not workspace and not is_help then
    --       return
    --     end
    --
    --     if buf_dir then
    --       Obsidian.buf_dir = Path.new(buf_dir)
    --     end
    --
    --     local opts = Obsidian.opts
    --
    --     vim.b[ev.buf].obsidian_buffer = true
    --
    --     if opts.comment.enabled then
    --       vim.o.commentstring = "%%%s%%"
    --     end
    --
    --     -- Register keymap.
    --     vim.keymap.set("n", "<CR>", api.smart_action, { expr = true, buffer = true, desc = "Obsidian Smart Action" })
    --
    --     vim.keymap.set("n", "]o", function()
    --       api.nav_link "next"
    --     end, { buffer = true, desc = "Obsidian Next Link" })
    --
    --     vim.keymap.set("n", "[o", function()
    --       api.nav_link "prev"
    --     end, { buffer = true, desc = "Obsidian Previous Link" })
    --
    --     -- Inject completion sources, providers to their plugin configurations
    --     if opts.completion.nvim_cmp then
    --       require("obsidian.completion.plugin_initializers.nvim_cmp").inject_sources(opts)
    --     elseif opts.completion.blink then
    --       require("obsidian.completion.plugin_initializers.blink").inject_sources(opts)
    --     end
    --
    --     require("obsidian.lsp").start(ev.buf)
    --
    --     exec_autocmds "ObsidianNoteEnter"
    --   end,
    -- })
    --
    -- vim.api.nvim_create_autocmd({ "BufLeave" }, {
    --   group = group,
    --   pattern = "*.md",
    --   callback = function(ev)
    --     if not vim.b[ev.buf].obsidian_buffer then
    --       return
    --     end
    --     exec_autocmds "ObsidianNoteLeave"
    --   end,
    -- })
    --
    -- -- Add/update frontmatter for notes before writing.
    -- vim.api.nvim_create_autocmd({ "BufWritePre" }, {
    --   group = group,
    --   pattern = "*.md",
    --   callback = function(ev)
    --     if not vim.b[ev.buf].obsidian_buffer then
    --       return
    --     end
    --
    --     -- Initialize note.
    --     local bufnr = ev.buf
    --     local note = Note.from_buffer(bufnr)
    --
    --     exec_autocmds "ObsidianNoteWritePre"
    --
    --     -- Update buffer with new frontmatter.
    --     note:update_frontmatter(bufnr)
    --   end,
    -- })
    --
    -- vim.api.nvim_create_autocmd({ "BufWritePost" }, {
    --   group = group,
    --   pattern = "*.md",
    --   callback = function(ev)
    --     if not vim.b[ev.buf].obsidian_buffer then
    --       return
    --     end
    --     exec_autocmds "ObsidianNoteWritePost"
    -- >>>>>>> e3cf180 (wip: attach for help buffers)
  end,
})

-- Run enter_note callback.
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteEnter",
  callback = function(ev)
    util.fire_callback("enter_note", Obsidian.opts.callbacks.enter_note, Note.from_buffer(ev.buf))
  end,
})

-- Run leave_note callback.
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteLeave",
  callback = function(ev)
    util.fire_callback("leave_note", Obsidian.opts.callbacks.leave_note, Note.from_buffer(ev.buf))
  end,
})

-- Run pre_write_note callback
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteWritePre",
  callback = function(ev)
    util.fire_callback("pre_write_note", Obsidian.opts.callbacks.pre_write_note, Note.from_buffer(ev.buf))
  end,
})
