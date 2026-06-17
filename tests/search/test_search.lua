local M = require "obsidian.search"
local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_refs"] = new_set()

T["find_refs"]["should find positions of all refs"] = function()
  local s = "[[Foo]] [[foo|Bar]]"
  eq({ { 1, 7, "Wiki", "[[Foo]]" }, { 9, 19, "WikiWithAlias", "[[foo|Bar]]" } }, M.find_refs(s))
end

T["find_refs"]["should include embed markers"] = function()
  local s = "![[Foo]] ![alt](foo.png)"
  eq({ { 1, 8, "Wiki", "![[Foo]]" }, { 10, 24, "Markdown", "![alt](foo.png)" } }, M.find_refs(s))
end

T["find_refs"]["should ignore refs within an inline code block"] = function()
  local s = "`[[Foo]]` [[foo|Bar]]"
  eq({ { 11, 21, "WikiWithAlias", "[[foo|Bar]]" } }, M.find_refs(s))

  s = "[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (triggered by typing `[[` for wiki links or "
    .. "just `[` for markdown links), powered by [`ripgrep`](https://github.com/BurntSushi/ripgrep)"
  eq({
    {
      1,
      47,
      "Markdown",
      "[nvim-cmp](https://github.com/hrsh7th/nvim-cmp)",
    },
    {
      134,
      183,
      "Markdown",
      "[`ripgrep`](https://github.com/BurntSushi/ripgrep)",
    },
  }, M.find_refs(s))
end

T["find_refs"]["should find footnote refs"] = function()
  local s = "some claim[^1] and [^note]"
  eq({ { 11, 14, "Footnote", "[^1]" }, { 20, 26, "Footnote", "[^note]" } }, M.find_refs(s))
end

T["find_refs"]["should find footnote refs in definition lines"] = function()
  local s = "[^1]: the footnote text"
  eq({ { 1, 4, "Footnote", "[^1]" } }, M.find_refs(s))
end

T["find_refs"]["should prefer footnote over markdown link"] = function()
  local s = "claim[^fn](not a link)"
  eq({ { 6, 10, "Footnote", "[^fn]" } }, M.find_refs(s))
end

T["find_refs"]["should not match block wiki links as footnotes"] = function()
  local s = "[[^block]]"
  eq({ { 1, 10, "Wiki", "[[^block]]" } }, M.find_refs(s))
end

T["find_matches"] = function()
  local matches = M.find_matches(
    [[
- <https://youtube.com@Fireship>
- [Fireship](https://youtube.com@Fireship)
  ]],
    { "Markdown" }
  )
  eq(1, #matches)
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

return T
