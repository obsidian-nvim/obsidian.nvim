local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local T = h.temp_vault

local picker = require "obsidian.picker"
local search = require "obsidian.search"

T["attachment picker"] = new_set()

T["attachment picker"]["filters attachment types and applies queries to relative paths"] = function()
  local root = tostring(Obsidian.dir)
  local image = vim.fs.joinpath(root, "media", "image.png")
  local note = vim.fs.joinpath(root, "media", "note.md")
  local other = vim.fs.joinpath(root, "other.pdf")
  vim.fn.mkdir(vim.fs.dirname(image), "p")
  vim.fn.writefile({ "image" }, image)
  vim.fn.writefile({ "note" }, note)
  vim.fn.writefile({ "pdf" }, other)

  local original_find_async = search.find_async
  local original_select = picker.select
  local captured
  local selected
  search.find_async = function(dir, _, _, on_match, on_exit)
    eq(root, tostring(dir))
    on_match(image)
    on_match(note)
    on_match(other)
    on_exit(0)
    return function() end
  end
  picker.select = function(values, opts, callback)
    captured = { values = values, opts = opts }
    callback { values[1] }
  end

  picker.find_attachments {
    query = "media",
    callback = function(paths)
      selected = paths
    end,
  }

  search.find_async = original_find_async
  picker.select = original_select

  eq(1, #captured.values)
  eq("media/image.png", captured.values[1].text)
  eq({ image }, selected)
  eq(true, captured.values[1].user_data.attachment)
end

return T
