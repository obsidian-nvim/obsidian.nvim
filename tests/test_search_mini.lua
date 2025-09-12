local M = require "obsidian.search"
local h = dofile "tests/helpers.lua"
local child

local RefTypes, SearchOpts = M.RefTypes, M.SearchOpts

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

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
    { RefTypes.NakedUrl }
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
  eq({ { 10, 17, RefTypes.Tag } }, M.find_tags_in_string(s))
  s = [[\#notatag]]
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore issue numbers"] = function()
  local s = "Issue: #100"
  eq({}, M.find_tags_in_string(s))
end

T["find_tags_in_string"]["should ignore hexcolors"] = function()
  local s = "backgroud: #f0f0f0"
  eq({}, M.find_tags_in_string(s))
end

-- T["find_tags_in_string"]["should ignore anchor links that look like tags"] = function()
--   local s = "[readme](README#installation)"
--   eq({}, M.find_tags_in_string(s))
-- end
--
-- T["find_tags_in_string"]["should ignore section in urls"] = function()
--   local s = "https://example.com/page#section"
--   eq({}, M.find_tags_in_string(s))
-- end
--
-- T["find_tags_in_string"]["should ignore tags in HTML entities"] = function()
--   eq({}, M.find_tags_in_string "Here is an entity: &#NOT_A_TAG;")
-- end
--
--
-- T["find_tags_in_string"]["should ignore tags not on word boundaries"] = function()
--   eq({}, M.find_tags_in_string "foobar#notatag")
--   eq({ { 9, 12, RefTypes.Tag } }, M.find_tags_in_string "foo bar #tag")
-- end
--
-- T["find_tags_in_string"]["should ignore tags in markdown links with parentheses"] = function()
--   local s = "[autobox](https://en.wikipedia.org/wiki/Object_type_(object-oriented_programming)#NOT_A_TAG)"
--   eq({}, M.find_tags_in_string(s))
-- end

--
-- T["find_tags_in_string"]["should find non-English tags"] = function()
--   eq(1, M.find_tags_in_string " #你好")
--   eq(1, M.find_tags_in_string " #タグ")
--   eq(1, M.find_tags_in_string " #mañana")
--   eq(1, M.find_tags_in_string " #день")
--   eq(1, M.find_tags_in_string " #项目_计划")
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

T["find_links"], child = h.new_set_with_setup()

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
