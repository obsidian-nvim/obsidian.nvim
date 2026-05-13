local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()
local h = dofile "tests/helpers.lua"
local child

T["parse"], child = h.child_vault {
  pre_case = [[M = require "obsidian.bookmarks"]],
}

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

T["parse"]["decodes bookmarks.json into items"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["nvim.md"] = "^archive\n",
    [".obsidian/bookmarks.json"] = example_json,
  })

  child.lua [[
local fp = M.resolve_bookmark_file()
assert(fp, "resolve_bookmark_file returned nil")

local f = io.open(fp, "r")
assert(f, "Failed to open bookmarks file")
local src = f:read "*a"
f:close()
_G.res = M.parse(src)
]]

  local result = child.lua_get [[res]]

  eq(#result, 8)
  eq(result[1].type, "file")
  eq(result[1].path, "todo.md")
  eq(result[1].title, "TODOs")

  eq(result[3].type, "group")
  eq(#result[3].items, 1)
  eq(result[3].items[1].path, "Projects/nvim/archived.md")

  eq(result[4].type, "file")
  eq(result[4].subpath, "#^archive")

  eq(result[5].type, "search")
  eq(result[5].query, "neovim")

  eq(result[8].type, "url")
  eq(result[8].url, "https://chatgpt.com/")
end

return T
