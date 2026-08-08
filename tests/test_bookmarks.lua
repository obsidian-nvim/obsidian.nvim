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

T["parse"]["blinks anchor target range"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Heading\nbody\n\n# Next\n",
  })

  local blinked = child.lua [[
local picker = require "obsidian.picker"
picker.select = function(items, _, callback)
  callback { items[1] }
end

M.pick {
  {
    type = "file",
    path = "note.md",
    subpath = "#Heading",
    title = "Heading",
  },
}

local bufnr = vim.api.nvim_get_current_buf()
for name, ns in pairs(vim.api.nvim_get_namespaces()) do
  if name:match("^obsidian_blink_") and #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}) > 0 then
    return true
  end
end
return false
]]

  eq(true, blinked)
end

T["parse"]["preview buffers are wiped when hidden"] = function()
  child.lua [[
local picker = require "obsidian.picker"
picker.select = function(items, opts)
  local preview = opts.preview_item(items[1])
  _G.preview_bufhidden = vim.bo[preview.buf].bufhidden
end

M.pick {
  {
    type = "search",
    query = "neovim",
    title = "neovim search",
  },
}
]]

  eq("wipe", child.lua_get [[preview_bufhidden]])
end

T["parse"]["resolves search bookmarks with Obsidian query syntax"] = function()
  local dir = child.Obsidian.dir
  h.mock_vault_contents(dir, {
    ["draft.md"] = "---\nstatus: Draft\ntags: [work]\n---\n# Draft\nneedle\n",
    ["done.md"] = "---\nstatus: Done\ntags: [work]\n---\n# Done\nneedle\n",
    ["personal.md"] = "# Personal\n#friends\n",
  })

  local result = h.child_await(
    child,
    [[
local api = require "obsidian.api"
local picker = require "obsidian.picker"
local picker_calls = 0
local resolved

picker.select = function(items, opts, callback)
  picker_calls = picker_calls + 1
  if picker_calls == 1 then
    callback { items[1] }
    return
  end

  resolved = {
    count = #items,
    prompt = opts.prompt,
    allow_multiple = opts.allow_multiple,
    filename = items[1].filename,
    lnum = items[1].lnum,
    col = items[1].col,
  }
  callback { items[1] }
end

api.open_note = function(entry)
  resolved.opened = entry.filename
  done(resolved)
end

M.pick {
  {
    type = "search",
    query = "tag:#work -[status:Done]",
    title = "Open work",
  },
}
]],
    { desc = "bookmark query results" }
  )

  local expected = vim.fs.joinpath(tostring(dir), "draft.md")
  eq(1, result.count)
  eq("Search: Open work", result.prompt)
  eq(true, result.allow_multiple)
  eq(vim.fs.normalize(expected), vim.fs.normalize(result.filename))
  eq(1, result.lnum)
  eq(1, result.col)
  eq(vim.fs.normalize(expected), vim.fs.normalize(result.opened))
end

T["parse"]["rejects invalid bookmark queries before indexing"] = function()
  local result = h.child_await(
    child,
    [[
local index = require "obsidian.search.index"
local log = require "obsidian.log"
local picker = require "obsidian.picker"
local indexed = false

index.index_async = function()
  indexed = true
end
log.err = function(fmt, ...)
  done { indexed = indexed, message = string.format(fmt, ...) }
end
picker.select = function(items, _, callback)
  callback { items[1] }
end

M.pick {
  {
    type = "search",
    query = '"unfinished',
    title = "Broken",
  },
}
]],
    { desc = "invalid bookmark query error" }
  )

  eq(false, result.indexed)
  eq("Invalid bookmark search query: Unclosed phrase at column 1", result.message)
end

return T
