local builtin = require "obsidian.builtin"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local Path = require "obsidian.path"

local T = new_set {
  hooks = {
    pre_case = function()
      local path = Path.temp()
      path:mkdir()
      require("obsidian").setup {
        workspaces = {
          {
            path = tostring(path),
          },
        },
      }
    end,
    post_case = function()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

T["img_text_func"] = new_set()

T["img_text_func"] = function()
  local mock_file = vim.fs.joinpath(tostring(Obsidian.dir), Obsidian.opts.attachments.img_folder, "test file.png")
  eq("![[test file.png]]", builtin.img_text_func(mock_file))
  Obsidian.opts.preferred_link_style = "markdown"
  eq("![](test%20file.png)", builtin.img_text_func(mock_file))
end

return T
