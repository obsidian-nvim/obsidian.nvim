local builtin = require "obsidian.builtin"
local attachment = require "obsidian.attachment"
local actions = require "obsidian.actions"
local log = require "obsidian.log"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T = h.temp_vault

T["img_text_func"] = new_set()

T["img_text_func"] = function()
  local mock_file = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "test file.png")
  eq("![[test file.png]]", builtin.img_text_func(mock_file))
  Obsidian.opts.link.style = "markdown"
  eq("![](test%20file.png)", builtin.img_text_func(mock_file))
end

T["format_link"] = new_set()

T["format_link"]["markdown links should URL-encode basename"] = function()
  Obsidian.opts.link.style = "markdown"
  local mock_file = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.folder, "test file (1).png")
  eq("![](test%20file%20%281%29.png)", attachment.format_link(mock_file))
end

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
  local captured_add
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[bufnr].obsidian_buffer = true

  vim.ui.input = function(_, callback)
    callback "picked.png"
  end
  attachment.add = function(src, opts)
    captured_add = { src = src, opts = opts }
  end

  local ok, err = pcall(actions.add_attachment, nil, { insert = false, bufnr = bufnr, new_name = "renamed.png" })

  vim.ui.input = original_input
  attachment.add = original_add

  if not ok then
    error(err)
  end

  eq(false, captured_add.opts.insert)
  eq(bufnr, captured_add.opts.bufnr)
  eq("renamed.png", captured_add.opts.new_name)
end

return T
