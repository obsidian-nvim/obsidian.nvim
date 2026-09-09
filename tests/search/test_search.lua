local M = require "obsidian.search"
local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_code_blocks"] = new_set()

T["find_code_blocks"]["should find generic code blocks"] = function()
  ---@type string[]
  local lines
  local results = {
    { 3, 6 },
  }

  -- no indentation
  lines = {
    "this is a python function:",
    "",
    "```",
    "def foo():",
    "    pass",
    "```",
    "",
  }
  eq(results, M.find_code_blocks(lines))

  -- indentation
  lines = {
    "  this is a python function:",
    "",
    "  ```",
    "  def foo():",
    "      pass",
    "  ```",
    "",
  }
  eq(results, M.find_code_blocks(lines))
end

T["find_code_blocks"]["should find generic inline code blocks"] = function()
  ---@type string[]
  local lines
  local results = {
    { 3, 3 },
  }

  -- no indentation
  lines = {
    "this is a python function:",
    "",
    "```lambda x: x + 1```",
    "",
  }
  eq(results, M.find_code_blocks(lines))

  -- indentation
  lines = {
    "  this is a python function:",
    "",
    "  ```lambda x: x + 1```",
    "",
  }
  eq(results, M.find_code_blocks(lines))
end

T["find_code_blocks"]["should find lang-specific code blocks"] = function()
  ---@type string[]
  local lines
  local results = {
    { 3, 6 },
  }

  -- no indentation
  lines = {
    "this is a python function:",
    "",
    "```python",
    "def foo():",
    "    pass",
    "```",
    "",
  }
  eq(results, M.find_code_blocks(lines))

  -- indentation
  lines = {
    "  this is a python function:",
    "",
    "  ```",
    "  def foo():",
    "      pass",
    "  ```",
    "",
  }
  eq(results, M.find_code_blocks(lines))
end

T["find_code_blocks"]["should find lang-specific inline code blocks"] = function()
  ---@type string[]
  local lines
  local results = {
    { 3, 3 },
  }

  -- no indentation
  lines = {
    "this is a python function:",
    "",
    "```{python} lambda x: x + 1```",
    "",
  }
  eq(results, M.find_code_blocks(lines))

  -- indentation
  lines = {
    "  this is a python function:",
    "",
    "  ```{python} lambda x: x + 1```",
    "",
  }
  eq(results, M.find_code_blocks(lines))
end

T["find_links"], child = h.child_vault()

T["find_links"]["should find all links in a file"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "test.md")
  local file = [==[
[[link]]
  https://neovim.io <- barelinks should not work
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)
  child.lua [[
local search = require"obsidian.search"
local note = require"obsidian.note".from_file(tostring(Obsidian.dir / "test.md"))
_G.res = search.find_links(note, {})
  ]]
  local res = child.lua_get [[res]]

  eq({
    {
      ["end"] = 7,
      line = 1,
      link = "[[link]]",
      start = 0,
    },
  }, res)
end

local find_notes_child
T["find_notes"], find_notes_child = h.child_vault {
  pre_case = [[
vim.fn.writefile({ "# Shared note" }, tostring(Obsidian.dir / "shared-note.md"))
vim.fn.writefile({ "# Shared template" }, tostring(Obsidian.dir / "templates" / "shared-template.md"))
vim.fn.writefile({ "filters: shared" }, tostring(Obsidian.dir / "shared.base"))
vim.fn.writefile({ '{"text":"shared"}' }, tostring(Obsidian.dir / "shared.canvas"))
vim.fn.writefile({ '{"text":"shared"}' }, tostring(Obsidian.dir / "shared.excalidraw"))
local archive = Obsidian.dir / "archive"
archive:mkdir()
vim.fn.writefile({ "# Shared archive" }, tostring(archive / "shared-archive.md"))
Obsidian.opts.file.ignore_filters = { "archive" }
require("obsidian.cache").setup { enabled = true, backend = "memory" }
  ]],
}

T["find_notes"]["applies search exclusions to cached symbol lookups"] = function()
  local result = h.child_await(
    find_notes_child,
    [[
local search = require "obsidian.search"
local pending = 3
local result = {}
local function collect(key)
  return function(notes)
    result[key] = vim.tbl_map(function(note)
      return note.path.name
    end, notes)
    pending = pending - 1
    if pending == 0 then
      done(result)
    end
  end
end
search.find_notes_async("shared", collect("default"), { symbols_only = true })
search.find_notes_async("shared", collect("with_templates"), {
  symbols_only = true,
  search = { include_templates = true },
})
search.find_notes_async("shared", collect("filesystem"), { symbols_only = false })
  ]],
    { desc = "cached note searches" }
  )

  eq({ "shared-note.md" }, result.default)
  eq({ "shared-note.md" }, result.filesystem)
  eq({ "shared-note.md", "shared-template.md" }, result.with_templates)
end

return T
