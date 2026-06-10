local api = require "obsidian.api"
local actions = require "obsidian.actions"
local util = require "obsidian.util"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local ignore = require "obsidian.ignore"
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

  -- Check if this file should be ignored based on file.ignore_filters.
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
      actions.nav_link "next"
    end, { buffer = true, desc = "Obsidian Next Link" })

    vim.keymap.set("n", "[o", function()
      actions.nav_link "prev"
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
    create_autocmd("BufWritePre", args.buf, function(ev)
      if not vim.b[ev.buf].obsidian_buffer then
        return
      end

      exec_autocmds "ObsidianNoteWritePre"
      local note = Note.from_buffer(ev.buf)
      if not vim.b[ev.buf].obsidian_help then
        note:update_frontmatter(ev.buf) -- Update buffer with new frontmatter.
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

---Strip shell quoting some terminals apply to drag-and-dropped paths.
---@param line string
---@return string
local function strip_quotes(line)
  local unquoted = line:match "^'(.*)'$" or line:match '^"(.*)"$'
  return unquoted or line
end

---Handle a single pasted (or drag-and-dropped) line if it is a URL or a local
---file, returning true when it was consumed.
---@param line string
---@return boolean handled
local function smart_paste_line(line)
  line = strip_quotes(vim.trim(line))

  local actions = require "obsidian.actions"

  if line:match "^https?://%S+$" then
    actions.paste_url(line)
    return true
  end

  local path = line
  if vim.startswith(line, "file://") then
    local ok, fname = pcall(vim.uri_to_fname, line)
    if not ok then
      return false
    end
    path = fname
  end

  if path:match "^[~/]" and vim.uv.fs_stat(vim.fs.normalize(path)) then
    actions.add_attachment(path, { insert = true })
    return true
  end

  return false
end

-- Intercept paste streams in obsidian buffers, so URLs and file paths
-- drag-and-dropped from terminals (which arrive as bracketed paste) are turned
-- into markdown links and attachments automatically.
if Obsidian.opts.paste.drag_and_drop then
  vim.paste = (function(overridden)
    ---@param lines string[]
    ---@param phase integer
    return function(lines, phase)
      -- only complete, single-line pastes in obsidian buffers, outside cmdline
      if not vim.b.obsidian_buffer or phase ~= -1 or #lines ~= 1 or vim.fn.mode():sub(1, 1) == "c" then
        return overridden(lines, phase)
      end

      if smart_paste_line(lines[1]) then
        return true
      end

      return overridden(lines, phase)
    end
  end)(vim.paste)
end

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
    if not ws then
      return
    end
    local sync = require "obsidian.sync"
    if not sync.is_configured(ws) then
      return
    end
    sync.sync_once_debounced(ws)
  end,
})
