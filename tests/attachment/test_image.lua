local builtin = require "obsidian.builtin"
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

return T
