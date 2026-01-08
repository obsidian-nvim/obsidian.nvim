local M = require "obsidian.bookmarks"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()
local h = dofile "tests/helpers.lua"
local child

T["parse"], child = h.child_vault {
  pre_case = [[M = require "obsidian.bookmarks"]],
}

local src = [[
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
]]

local example_json = [[
{
  "items": [
    {
      "type": "file",
      "ctime": 1764611279166,
      "path": "todo.md",
      "title": "TODOs"
    },
    {
      "type": "folder",
      "ctime": 1764611343536,
      "path": "Projects/nvim",
      "title": "neovim"
    },
    {
      "type": "group",
      "ctime": 1764856070428,
      "items": [
        {
          "type": "file",
          "ctime": 1764611543232,
          "path": "Projects/nvim/archived.md",
          "subpath": "#EdenEast/nightfox.nvim",
          "title": "a heading"
        }
      ],
      "title": "group 1"
    },
    {
      "type": "file",
      "ctime": 1764865200095,
      "path": "Projects/nvim/archived.md",
      "subpath": "#^archive"
    },
    {
      "type": "search",
      "ctime": 1764891189524,
      "query": "neovim",
      "title": "neovim search"
    },
    {
      "type": "file",
      "ctime": 1767395756461,
      "path": "Bases/2026 Music.base"
    },
    {
      "type": "file",
      "ctime": 1767541143465,
      "path": "Bases/2026 Movies.base"
    },
    {
      "type": "url",
      "ctime": 1767874757801,
      "url": "https://chatgpt.com/",
      "title": "ChatGPT"
    }
  ]
}]]

T["parse"]["expand group as a flat list"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["nvim.md"] = [[
^archive
     ]],
    [".obsidian/bookmarks.json"] = example_json,
  })

  child.lua [[
local fp = M.resolve_bookmark_file()
if not fp then
 return
end

local f = io.open(fp, "r")
assert(f, "Failed to open bookmarks file")
local src = f:read "*a"
f:close()
_G.res = M.parse(src)
]]

  local result = child.lua_get [[res]]

  eq(result[5], {
    filename = "/home/n451/Vaults/1 Notes/nested.md",
    text = "nested",
  })
end

-- T["parse"]["keep group with a callback to open new picker"] = function()
--   Obsidian.opts.bookmarks.group = true
--   local result = M._parse(items)
--
--   eq(result[5].text, "a group")
--   eq(type(result[5].user_data), "function")
-- end

return T
