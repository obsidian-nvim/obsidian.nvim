local M = require "obsidian.search"
local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_refs"] = new_set()

T["find_refs"]["should find positions of all refs"] = function()
  local s = "[[Foo]] [[foo|Bar]]"
  MiniTest.expect.equality({ { 1, 7, "Wiki" }, { 9, 19, "WikiWithAlias" } }, M.find_refs(s))
end

T["find_refs"]["should ignore refs within an inline code block"] = function()
  local s = "`[[Foo]]` [[foo|Bar]]"
  MiniTest.expect.equality({ { 11, 21, "WikiWithAlias" } }, M.find_refs(s))

  s = "[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (triggered by typing `[[` for wiki links or "
    .. "just `[` for markdown links), powered by [`ripgrep`](https://github.com/BurntSushi/ripgrep)"
  MiniTest.expect.equality(
    { { 1, 47, "Markdown" }, { 134, 183, "Markdown" } },
    M.find_refs(s, {
      exclude = { "NakedUrl" },
    })
  )
end

T["find_refs"]["should find block IDs at the end of a line"] = function()
  MiniTest.expect.equality(
    { { 14, 25, "BlockID" } },
    M.find_refs("Hello World! ^hello-world", { include_block_ids = true })
  )
end

T["find_matches"] = function()
  local matches = M.find_matches(
    [[
- <https://youtube.com@Fireship>
- [Fireship](https://youtube.com@Fireship)
  ]],
    { "NakedUrl" }
  )
  eq(2, #matches)
end

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
  -- TODO: any link protocol
  local file = [==[
[[link]]
  https://neovim.io
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)
  child.lua [[
local search = require"obsidian.search"
local note = require"obsidian.note".from_file(tostring(Obsidian.dir / "test.md"))
_G.res = search.find_links(note, {})
  ]]
  vim.uv.sleep(100)
  local res = child.lua_get [[res]]

  eq({
    {
      ["end"] = 7,
      line = 1,
      link = "[[link]]",
      start = 0,
    },
    {
      ["end"] = 18,
      line = 2,
      link = "https://neovim.io",
      start = 2,
    },
  }, res)
end

return T
