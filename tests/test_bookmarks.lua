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

T["groups"], child = h.child_vault {
  pre_case = [[M = require "obsidian.bookmarks"]],
}

T["groups"]["moves a bookmark into an existing group"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Note\n",
    [".obsidian/bookmarks.json"] = vim.json.encode {
      items = {
        { type = "file", ctime = 1, path = "note.md" },
        { type = "group", ctime = 2, title = "Work", items = {} },
      },
    },
  })

  child.lua [[
local picker = require "obsidian.picker"
picker.select = function(items, opts, callback)
  _G.group_prompt = opts.prompt
  _G.group_labels = vim.tbl_map(opts.format_item, items)
  callback { items[1] }
end
M.move_to_group { type = "file", ctime = 1, path = "note.md" }
local f = assert(io.open(M.resolve_bookmark_file(), "r"))
_G.bookmarks = vim.json.decode(f:read "*a")
f:close()
]]

  eq("Move bookmark to group", child.lua_get [[group_prompt]])
  eq({ "Work", "+ Create new group" }, child.lua_get [[group_labels]])
  local bookmarks = child.lua_get [[bookmarks]]
  eq(1, #bookmarks.items)
  eq("group", bookmarks.items[1].type)
  eq(1, bookmarks.items[1].items[1].ctime)
end

T["groups"]["creates a new group when moving a bookmark"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Note\n",
    [".obsidian/bookmarks.json"] = vim.json.encode {
      items = {
        { type = "file", ctime = 1, path = "note.md" },
      },
    },
  })

  child.lua [[
local picker = require "obsidian.picker"
local api = require "obsidian.api"
picker.select = function(items, _, callback)
  callback { items[#items] }
end
api.input = function(prompt)
  _G.group_name_prompt = prompt
  return "Personal"
end
M.move_to_group { type = "file", ctime = 1, path = "note.md" }
local f = assert(io.open(M.resolve_bookmark_file(), "r"))
_G.bookmarks = vim.json.decode(f:read "*a")
f:close()
]]

  eq("New bookmark group name", child.lua_get [[group_name_prompt]])
  local bookmarks = child.lua_get [[bookmarks]]
  eq(1, #bookmarks.items)
  eq("Personal", bookmarks.items[1].title)
  eq(1, bookmarks.items[1].items[1].ctime)
end

T["groups"]["does not delete anything when a bookmark is missing"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    [".obsidian/bookmarks.json"] = vim.json.encode {
      items = {
        { type = "url", ctime = 1, url = "https://example.com" },
      },
    },
  })

  child.lua [[
_G.deleted = M.del { type = "url", ctime = 2, url = "https://example.org" }
local f = assert(io.open(M.resolve_bookmark_file(), "r"))
_G.bookmarks = vim.json.decode(f:read "*a")
f:close()
]]

  eq(false, child.lua_get [[deleted]])
  eq(1, #child.lua_get [[bookmarks.items]])
end

T["add"], child = h.child_vault {
  pre_case = [[
M = require "obsidian.bookmarks"
A = require "obsidian.actions"
  ]],
}

T["add"]["bookmarks current note when nothing under cursor"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Hello\n\nbody line\n",
  })

  child.lua(string.format(
    [[
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_win_set_cursor(0, { 3, 0 }) -- on "body line"
A.add_bookmark()

local fp = M.resolve_bookmark_file()
local f = io.open(fp, "r")
_G.src = f:read("*a")
f:close()
  ]],
    tostring(dir / "note.md")
  ))

  local src = child.lua_get [[src]]
  local obj = vim.json.decode(src)
  eq(#obj.items, 1)
  eq(obj.items[1].type, "file")
  eq(obj.items[1].path, "note.md")
end

T["add"]["bookmarks notes through the picker mapping"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Hello\n",
  })

  child.lua(string.format(
    [[
local mappings = require("obsidian.picker")._note_selection_mappings()
mappings["<C-b>"].callback(%q)
local fp = M.resolve_bookmark_file()
local f = assert(io.open(fp, "r"))
_G.src = f:read "*a"
f:close()
  ]],
    tostring(dir / "note.md")
  ))

  local obj = vim.json.decode(child.lua_get [[src]])
  eq(1, #obj.items)
  eq("file", obj.items[1].type)
  eq("note.md", obj.items[1].path)
end

T["add"]["bookmarks heading under cursor"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Hello\n\nbody line\n",
  })

  child.lua(string.format(
    [[
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
A.add_bookmark()

local fp = M.resolve_bookmark_file()
local f = io.open(fp, "r")
_G.src = f:read("*a")
f:close()
  ]],
    tostring(dir / "note.md")
  ))

  local src = child.lua_get [[src]]
  local obj = vim.json.decode(src)
  eq(#obj.items, 1)
  eq(obj.items[1].type, "file")
  eq(obj.items[1].subpath, "#Hello")
end

T["add"]["bookmarks block under cursor"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "intro line ^my-block\nnext\n",
  })

  child.lua(string.format(
    [[
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
A.add_bookmark()

local fp = M.resolve_bookmark_file()
local f = io.open(fp, "r")
_G.src = f:read("*a")
f:close()
  ]],
    tostring(dir / "note.md")
  ))

  local src = child.lua_get [[src]]
  local obj = vim.json.decode(src)
  eq(#obj.items, 1)
  eq(obj.items[1].type, "file")
  eq(obj.items[1].subpath, "#^my-block")
end

T["add"]["bookmarks url under cursor"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "see [ChatGPT](https://chatgpt.com/) please\n",
  })

  child.lua(string.format(
    [[
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_win_set_cursor(0, { 1, 8 }) -- inside the markdown link
A.add_bookmark()

local fp = M.resolve_bookmark_file()
local f = io.open(fp, "r")
_G.src = f:read("*a")
f:close()
  ]],
    tostring(dir / "note.md")
  ))

  local src = child.lua_get [[src]]
  local obj = vim.json.decode(src)
  eq(#obj.items, 1)
  eq(obj.items[1].type, "url")
  eq(obj.items[1].url, "https://chatgpt.com/")
  eq(obj.items[1].title, "ChatGPT")
end

T["add"]["dynamic code action title reflects context"] = function()
  local dir = child.Obsidian.dir

  h.mock_vault_contents(dir, {
    ["note.md"] = "# Hello\n\nsee [ChatGPT](https://chatgpt.com/)\n",
  })

  child.lua(string.format(
    [[
vim.cmd("edit " .. vim.fn.fnameescape(%q))
local action = require("obsidian.lsp.handlers._code_action").actions.add_bookmark

vim.api.nvim_win_set_cursor(0, { 1, 0 })
_G.t_heading = action.data.title()

vim.api.nvim_win_set_cursor(0, { 3, 8 })
_G.t_url = action.data.title()

vim.api.nvim_win_set_cursor(0, { 3, 0 })
_G.t_note = action.data.title()
  ]],
    tostring(dir / "note.md")
  ))

  eq(child.lua_get [[t_heading]], "Bookmark heading under cursor")
  eq(child.lua_get [[t_url]], "Bookmark URL under cursor")
  eq(child.lua_get [[t_note]], "Bookmark current note")
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
local cache = require "obsidian.cache"
local picker = require "obsidian.picker"
local picker_calls = 0
local resolved

cache.setup { enabled = true, backend = "memory" }
cache.when_ready(function()

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
end)
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
local log = require "obsidian.log"
local picker = require "obsidian.picker"

log.err = function(fmt, ...)
  done { message = string.format(fmt, ...) }
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

  eq("Invalid bookmark search query: Unclosed phrase at column 1", result.message)
end

return T
