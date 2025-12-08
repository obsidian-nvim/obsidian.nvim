local M = require "obsidian.bookmarks"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["parse"] = new_set()

local items = {
  {
    ctime = 1764611279166,
    path = "nvim.md",
    title = "neovim",
    type = "file",
  },
  {
    ctime = 1764611343536,
    path = "nvim",
    title = "neovim",
    type = "folder",
  },
  {
    ctime = 1764865200095,
    path = "nvim.md",
    subpath = "#^archive",
    type = "file",
  },
  {
    ctime = 1764891189524,
    query = "neovim",
    title = "neovim search",
    type = "search",
  },
  {
    ctime = 1764856070428,
    items = {
      {
        ctime = 1764611543232,
        path = "nested.md",
        title = "nested",
        type = "file",
      },
    },
    title = "a group",
    type = "group",
  },
}

T["parse"]["expand group as a flat list"] = function()
  local result = M._parse(items)

  eq(result[5], {
    filename = "/home/n451/Vaults/1 Notes/nested.md",
    text = "nested",
  })
end

T["parse"]["keep group with a callback to open new picker"] = function()
  Obsidian.opts.bookmarks.group = true
  local result = M._parse(items)

  eq(result[5].text, "a group")
  eq(type(result[5].user_data), "function")
end

return T
