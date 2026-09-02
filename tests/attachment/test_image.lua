local builtin = require "obsidian.builtin"
local attachment = require "obsidian.attachment"
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

T["format_link"]["absolute format uses a vault-relative path"] = function()
  local path = vim.fs.joinpath(tostring(Obsidian.dir), "assets", "diagram.png")
  eq("![[assets/diagram.png]]", attachment.format_link(path, { format = "absolute" }))
end

T["format_link"]["relative format omits a leading dot slash"] = function()
  local note = vim.fs.joinpath(tostring(Obsidian.dir), "notes", "note.md")
  local same_dir = vim.fs.joinpath(tostring(Obsidian.dir), "notes", "diagram.png")
  local other_dir = vim.fs.joinpath(tostring(Obsidian.dir), "assets", "diagram.png")

  eq("![[diagram.png]]", attachment.format_link(same_dir, { format = "relative", filename = note }))
  eq("![[../assets/diagram.png]]", attachment.format_link(other_dir, { format = "relative", filename = note }))
end

return T
