local M = require "obsidian.search"
local h = dofile "tests/helpers.lua"
local child

local SearchOpts = M.SearchOpts

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_and_replace_refs"] = function()
  local s, indices = M.find_and_replace_refs "[[Foo]] [[foo|Bar]]"
  local expected_s = "Foo Bar"
  local expected_indices = { { 1, 3 }, { 5, 7 } }
  MiniTest.expect.equality(s, expected_s)
  MiniTest.expect.equality(#indices, #expected_indices)
  for i = 1, #indices do
    MiniTest.expect.equality(indices[i][1], expected_indices[i][1])
    MiniTest.expect.equality(indices[i][2], expected_indices[i][2])
  end
end

T["search.replace_refs()"] = function()
  MiniTest.expect.equality(M.replace_refs "Hi there [[foo|Bar]]", "Hi there Bar")
  MiniTest.expect.equality(M.replace_refs "Hi there [[Bar]]", "Hi there Bar")
  MiniTest.expect.equality(M.replace_refs "Hi there [Bar](foo)", "Hi there Bar")
  MiniTest.expect.equality(M.replace_refs "Hi there [[foo|Bar]] [[Baz]]", "Hi there Bar Baz")
end

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

T["SearchOpts"] = new_set()

T["SearchOpts"]["should initialize from a raw table and resolve to ripgrep options"] = function()
  local opts = {
    sort_by = "modified",
    fixed_strings = true,
    ignore_case = true,
    exclude = { "templates" },
    max_count_per_file = 1,
  }
  eq(
    SearchOpts.to_ripgrep_opts(opts),
    { "--sortr=modified", "--fixed-strings", "--ignore-case", "-g!templates", "-m=1" }
  )
end

T["SearchOpts"]["should not include any options with defaults"] = function()
  eq(SearchOpts.to_ripgrep_opts {}, {})
end

T["SearchOpts"]["should merge with another SearchOpts instance"] = function()
  local opts1 = { fixed_strings = true, max_count_per_file = 1 }
  local opts2 = { fixed_strings = false, ignore_case = true }
  local opt = SearchOpts.merge(opts1, opts2)
  eq(SearchOpts.to_ripgrep_opts(opt), { "--ignore-case", "-m=1" })
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

T["find_tags_in_string"] = new_set()

T["find_tags_in_string"]["should find positions of all tags"] = function()
  local s = "#TODO I have a #meeting at noon"
  eq({ { 1, 5, "Tag" }, { 16, 23, "Tag" } }, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should find four cases"] = function()
  eq(1, #M.find_tags_in_string "#camelCase")
  eq(1, #M.find_tags_in_string "#PascalCase")
  eq(1, #M.find_tags_in_string "#snake_case")
  eq(1, #M.find_tags_in_string "#kebab-case")
end

T["find_tags_in_string"]["should find nested tags"] = function()
  eq(1, #M.find_tags_in_string " #inbox/processing")
  eq(1, #M.find_tags_in_string " #inbox/to-read")
end

T["find_tags_in_string"]["should ignore escaped tags"] = function()
  local s = "I have a #meeting at noon \\#not-a-tag"
  eq({ { 10, 17, "Tag" } }, M.find_tags_in_string(s))
  s = [[\#notatag]]
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore issue numbers"] = function()
  local s = "Issue: #100"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore hexcolors"] = function()
  local s = "background: #f0f0f0"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore anchor links that look like tags"] = function()
  local s = "[readme](README#installation)"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore section in urls"] = function()
  local s = "https://example.com/page#section"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore tags in HTML entities"] = function()
  eq({}, M.find_tags_in_string "Here is an entity: &#NOT_A_TAG;")
end

T["find_tags_in_string"]["should ignore tags not on word boundaries"] = function()
  eq({}, M.find_tags_in_string "foobar#notatag")
  eq({ { 9, 12, "Tag" } }, M.find_tags_in_string "foo bar #tag")
end

T["find_tags_in_string"]["should ignore tags in markdown links with parentheses"] = function()
  local s = "[autobox](https://en.wikipedia.org/wiki/Object_type_(object-oriented_programming)#NOT_A_TAG)"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore tags in html comments"] = function()
  local s = "<!-- #region -->"
  eq({}, M.find_tags_in_string(s))
end

-- TODO: unicode tags
-- T["find_tags_in_string"]["should find non-English tags"] = function()
-- eq(1, M.find_tags_in_string "#你好")
-- eq(1, M.find_tags_in_string "#タグ")
-- eq(1, M.find_tags_in_string "#mañana")
-- eq(1, M.find_tags_in_string "#день")
-- eq(1, M.find_tags_in_string "#项目_计划")
-- end

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
