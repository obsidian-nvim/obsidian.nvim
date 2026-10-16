local api = require "obsidian.api"
local actions = require "obsidian.actions"
local util = require "obsidian.util"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local ignore = require "obsidian.ignore"
local Workspace = require "obsidian.workspace"
local frecency = require "obsidian.frecency"
local fs_util = require "obsidian.util.fs"
local group = vim.api.nvim_create_augroup("obsidian_setup", { clear = true })

-- Track note visits independently from the optional metadata cache. Deferred
-- until other BufEnter callbacks have had a chance to switch workspaces.
vim.api.nvim_create_autocmd("BufEnter", {
  group = group,
  callback = function(ev)
    local path = vim.api.nvim_buf_get_name(ev.buf)
    if path == "" then
      return
    end

    vim.schedule(function()
      local workspace = api.find_workspace(path)
      if not workspace or not api.path_is_note(path, workspace) then
        return
      end

      local opts = api._workspace_opts(workspace)
      local ignore_checker = ignore._build_ignore_checker(opts.file and opts.file.ignore_filters or {})
      if ignore_checker then
        local rel_path = fs_util.relpath(tostring(workspace.root), path)
        if rel_path and ignore_checker(rel_path) then
          return
        end
      end

      frecency.record(path, tostring(workspace.root))
    end)
  end,
})

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
  if not workspace or not api.path_is_note(ev.file, workspace) then
    return
  end

  if workspace ~= Obsidian.workspace then
    Workspace.set(workspace)
  end

  -- Check if this file should be ignored based on this workspace's file.ignore_filters.
  if ignore.is_ignored(ev.file) then
    return
  end

  if workspace.name == ".obsidian.wiki" then
    vim.bo[ev.buf].readonly = true
    vim.b[ev.buf].obsidian_help = true
  end

  local opts = Obsidian.opts

  vim.b[ev.buf].obsidian_buffer = true
  vim.bo[ev.buf].includeexpr = "v:lua.require('obsidian.link').includeexpr(v:fname)"

  if opts.comment.enabled then
    vim.o.commentstring = "%%%s%%"
  end

  -- Register keymap.
  if vim.g.obsidian_default_keymap ~= false then -- NOTE: not in config since not sure whether the confusion and the small interface is worth it, might remove in major release
    vim.keymap.set("n", "<CR>", actions.smart_action, { expr = true, buffer = true, desc = "Obsidian Smart Action" })

    vim.keymap.set("n", "]o", function()
      actions.nav_link("next", true)
    end, { buffer = true, desc = "Obsidian Next Link" })

    vim.keymap.set("n", "[o", function()
      actions.nav_link("prev", true)
    end, { buffer = true, desc = "Obsidian Previous Link" })
  end

  require("obsidian.lsp").start(ev.buf)

  if opts.footer.enabled then
    require("obsidian.footer").start(ev.buf)
  end

  exec_autocmds "ObsidianNoteEnter"
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "markdown", "quarto" },
  callback = function(args)
    create_autocmd("BufEnter", args.buf, bufenter_callback)
    create_autocmd("BufLeave", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      exec_autocmds "ObsidianNoteLeave"
    end)
    create_autocmd({ "InsertLeave", "TextChanged" }, args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      if ev.event == "InsertLeave" then
        require("obsidian.inlay_hints.completion").observe(ev.buf)
      end
      require("obsidian.inlay_hints").schedule_refresh(ev.buf)
    end)
    create_autocmd("CursorMovedI", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      local _, left_completion = require("obsidian.inlay_hints.completion").observe(ev.buf)
      if left_completion then
        require("obsidian.inlay_hints").schedule_refresh(ev.buf, { allow_insert = true })
      end
    end)
    create_autocmd("BufWritePre", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      exec_autocmds "ObsidianNoteWritePre"
      local note = Note.from_buffer(ev.buf)
      if not vim.b[ev.buf].obsidian_help then
        pcall(vim.cmd, "undojoin")
        note:update_frontmatter(ev.buf) -- Update buffer with new frontmatter.
        pcall(vim.cmd, "undojoin")
      end
    end)
    create_autocmd("BufWritePost", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end
      exec_autocmds "ObsidianNoteWritePost"
    end)
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

-- One-shot sync trigger on buffer write.
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "ObsidianNoteWritePost",
  callback = function(ev)
    local sync_opts = Obsidian.opts.sync
    if not sync_opts or not sync_opts.enabled or sync_opts.trigger ~= "on_write" then
      return
    end
    local fname = vim.api.nvim_buf_get_name(ev.buf or 0)
    local ws = api.find_workspace(fname)
    if not ws or not api.path_is_note(fname, ws) then
      return
    end
    local sync = require "obsidian.sync"
    if not sync.is_configured(ws) then
      return
    end
    sync.sync_once_debounced(ws)
  end,
})
