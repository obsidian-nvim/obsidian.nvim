local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local T = h.temp_vault
local attachment = require "obsidian.attachment"
local actions = require "obsidian.actions"
local log = require "obsidian.log"

T["add"] = new_set()

T["add"]["URL filenames should be decoded before basename resolution"] = function()
  local original_system = vim.system
  local original_executable = vim.fn.executable
  local captured_dst

  vim.system = function(cmd)
    captured_dst = cmd[5]
    return {
      wait = function()
        return { code = 0, stdout = "", stderr = "" }
      end,
    }
  end
  vim.fn.executable = function(cmd)
    if cmd == "curl" then
      return 1
    end
    return original_executable(cmd)
  end

  local ok, result = pcall(attachment.add, "https://example.com/%2e%2e%2fescape.png", { insert = false })

  vim.system = original_system
  vim.fn.executable = original_executable

  if not ok then
    error(result)
  end

  local expected = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "escape.png")
  eq(expected, captured_dst)
  eq(expected, result)
end

T["add"]["relative attachment folders should resolve against target buffer"] = function()
  Obsidian.opts.attachments.folder = "./"

  local subdir = vim.fs.joinpath(tostring(Obsidian.dir), "notes")
  vim.fn.mkdir(subdir, "p")
  local src = vim.fs.joinpath(tostring(Obsidian.dir), "source.png")
  vim.fn.writefile({ "image" }, src)

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, vim.fs.joinpath(subdir, "note.md"))

  local result = attachment.add(src, { insert = false, bufnr = bufnr })
  local expected = vim.fs.joinpath(subdir, "source.png")

  eq(expected, result)
  eq(1, vim.fn.filereadable(expected))
end

T["add"]["new_name should override destination basename"] = function()
  local src = vim.fs.joinpath(tostring(Obsidian.dir), "source.png")
  vim.fn.writefile({ "image" }, src)

  local result = attachment.add(src, { insert = false, new_name = "renamed.png" })
  local expected = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "renamed.png")

  eq(expected, result)
  eq(1, vim.fn.filereadable(expected))
end

T["add"]["new_name should reject paths"] = function()
  local original_err = log.err
  local src = vim.fs.joinpath(tostring(Obsidian.dir), "source.png")
  vim.fn.writefile({ "image" }, src)
  log.err = function() end

  local ok, result = pcall(attachment.add, src, { insert = false, new_name = "nested/renamed.png" })
  local expected = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "renamed.png")

  log.err = original_err

  if not ok then
    error(result)
  end

  eq(nil, result)
  eq(0, vim.fn.filereadable(expected))
end

T["add"]["should fire callback and autocmd with context"] = function()
  local src = vim.fs.joinpath(tostring(Obsidian.dir), "source.png")
  vim.fn.writefile({ "image" }, src)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local callback_data
  local autocmd_data
  local group = vim.api.nvim_create_augroup("obsidian_test_attachment", { clear = true })

  Obsidian.opts.callbacks.add_attachment = function(path, ctx)
    callback_data = { path = path, scope = ctx.scope, buffer = ctx.buffer }
  end
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ObsidianAttachmentAdded",
    callback = function(ev)
      autocmd_data = { path = ev.data.path, scope = ev.data.ctx.scope, buffer = ev.data.ctx.buffer }
    end,
  })

  local result = attachment.add(src, {
    insert = false,
    bufnr = bufnr,
    scope = "test_scope",
  })
  local expected = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "source.png")

  Obsidian.opts.callbacks.add_attachment = nil
  vim.api.nvim_del_augroup_by_id(group)

  eq(expected, result)
  eq({ path = expected, scope = "test_scope", buffer = bufnr }, callback_data)
  eq({ path = expected, scope = "test_scope", buffer = bufnr }, autocmd_data)
end

T["add"]["position option should insert at exact buffer position"] = function()
  local src = vim.fs.joinpath(tostring(Obsidian.dir), "source.png")
  vim.fn.writefile({ "image" }, src)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })

  attachment.add(src, { bufnr = bufnr, position = { row = 1, col = 3 } })

  local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
  eq("hel![[source.png]]lo", line)
end

T["actions"] = new_set()

T["actions"]["add_attachment should open picker for directory sources"] = function()
  local picker = require "obsidian.picker"
  local original_find_files = picker.find_files
  local original_add = attachment.add
  local captured_picker_opts
  local captured_add
  local dir = vim.fs.joinpath(tostring(Obsidian.dir), "sources")
  vim.fn.mkdir(dir, "p")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[bufnr].obsidian_buffer = true

  picker.find_files = function(opts)
    captured_picker_opts = opts
    opts.callback "picked.png"
  end
  attachment.add = function(src, opts)
    captured_add = { src = src, opts = opts }
  end

  local ok, err = pcall(actions.add_attachment, dir, { insert = false, bufnr = bufnr })

  picker.find_files = original_find_files
  attachment.add = original_add

  if not ok then
    error(err)
  end

  eq(dir, captured_picker_opts.dir)
  eq(true, captured_picker_opts.include_non_markdown)
  eq("picked.png", captured_add.src)
  eq(false, captured_add.opts.insert)
  eq(bufnr, captured_add.opts.bufnr)
end

T["actions"]["add_attachment prompt should preserve target buffer"] = function()
  local original_input = vim.ui.input
  local original_add = attachment.add
  local original_buf = vim.api.nvim_get_current_buf()
  local captured_add
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.b[bufnr].obsidian_buffer = true

  vim.ui.input = function(_, callback)
    callback "picked.png"
  end
  attachment.add = function(src, opts)
    captured_add = { src = src, opts = opts }
  end

  local ok, err = pcall(actions.add_attachment, nil, { insert = false, bufnr = bufnr, new_name = "renamed.png" })

  vim.api.nvim_set_current_buf(original_buf)
  vim.ui.input = original_input
  attachment.add = original_add

  if not ok then
    error(err)
  end

  eq(false, captured_add.opts.insert)
  eq(bufnr, captured_add.opts.bufnr)
  eq("renamed.png", captured_add.opts.new_name)
  eq("actions.add_attachment", captured_add.opts.scope)
end

return T
