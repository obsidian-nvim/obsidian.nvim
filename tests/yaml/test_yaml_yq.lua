local yaml = require "obsidian.yaml.yq"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

-- TODO: not run if no yq localy and not in CI?

T["should parse inline lists with quotes on items"] = function()
  local data = yaml.loads 'aliases: ["Foo", "Bar", "Foo Baz"]'
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 3)
  eq(data.aliases[3], "Foo Baz")

  data = yaml.loads 'aliases: ["Foo"]'
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 1)
  eq(data.aliases[1], "Foo")

  data = yaml.loads 'aliases: ["Foo Baz"]'
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 1)
  eq(data.aliases[1], "Foo Baz")
end

T["should parse inline lists without quotes on items"] = function()
  local data = yaml.loads "aliases: [Foo, Bar, Foo Baz]"
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 3)
  eq(data.aliases[3], "Foo Baz")

  data = yaml.loads "aliases: [Foo]"
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 1)
  eq(data.aliases[1], "Foo")

  data = yaml.loads "aliases: [Foo Baz]"
  eq(type(data), "table")
  eq(type(data.aliases), "table")
  eq(#data.aliases, 1)
  eq(data.aliases[1], "Foo Baz")
end

T["should parse boolean field values"] = function()
  local data = yaml.loads "complete: false"
  eq(type(data), "table")
  eq(type(data.complete), "boolean")
end

T["should parse implicit null values"] = function()
  local data = yaml.loads "tags: \ncomplete: false"
  eq(type(data), "table")
  eq(data.tags, vim.NIL)
  eq(data.complete, false)
end

-- TODO:

-- T["should parse strings with escaped quotes"] = function()
--   eq([["foo"]], yaml.loads [["\"foo\""]])
-- end

T["should parse numbers while trimming whitespace"] = function()
  eq(1, yaml.loads " 1")
  eq(1.5, yaml.loads " 1.5")
end

T["should parse booleans while trimming whitespace"] = function()
  eq(true, yaml.loads " true")
  eq(false, yaml.loads " false ")
end

T["should parse explicit null values while trimming whitespace"] = function()
  eq(vim.NIL, yaml.loads " null")
end

-- NOTE: no need?
-- T["should parse implicit null values"] = function()
--   eq(vim.NIL, yaml.loads " ")
-- end

-- T["should error when for invalid indentation"] = function()
--   local ok, err = pcall(function(str)
--     return yaml.loads(str)
--   end, " foo: 1\nbar: 2")
--   eq(false, ok)
--   assert(util.string_contains(err, "indentation"), err)
-- end

T["should parse root-level scalars"] = function()
  eq("a string", yaml.loads "a string")
  eq(true, yaml.loads "true")
end

-- T["should parse simple non-nested mappings"] = function()
--   local result = yaml.loads(table.concat({
--     "foo: 1",
--     "",
--     "bar: 2",
--     "baz: blah",
--     "some_bool: true",
--     "some_implicit_null:",
--     "some_explicit_null: null",
--   }, "\n"))
--   eq({
--     foo = 1,
--     bar = 2,
--     baz = "blah",
--     some_bool = true,
--     some_explicit_null = vim.NIL,
--     some_implicit_null = vim.NIL,
--   }, result)
-- end

T["should parse mappings with spaces for keys"] = function()
  local result = yaml.loads(table.concat({
    "bar: 2",
    "modification date: Tuesday 26th March 2024 18:01:42",
  }, "\n"))
  eq({
    bar = 2,
    ["modification date"] = "Tuesday 26th March 2024 18:01:42",
  }, result)
end

T["should parse mappings with parens for keys"] = function()
  local result = yaml.loads(table.concat({
    "bar: 5",
    "weight (Kg): 24",
    "Top speeds (m/s):",
    "- 5",
    "- 4.5",
    "- 2",
  }, "\n"))
  eq({
    bar = 5,
    ["weight (Kg)"] = 24,
    ["Top speeds (m/s)"] = { 5, 4.5, 2 },
  }, result)
end

T["should parse lists with or without extra indentation"] = function()
  local result = yaml.loads(table.concat({
    "foo:",
    "- 1",
    "- 2",
    "bar:",
    " - 3",
    " # ignore this comment",
    " - 4",
  }, "\n"))
  eq({
    foo = { 1, 2 },
    bar = { 3, 4 },
  }, result)
end

T["should parse a top-level list"] = function()
  local result = yaml.loads(table.concat({
    "- 1",
    "- 2",
    "# ignore this comment",
    "- 3",
  }, "\n"))
  eq({ 1, 2, 3 }, result)
end

T["should parse nested mapping"] = function()
  local result = yaml.loads [[
foo:
  bar: 1
  # ignore this comment
  baz: 2
    ]]
  eq({ foo = { bar = 1, baz = 2 } }, result)
end

T["should ignore comments"] = function()
  local result = yaml.loads(table.concat({
    "foo: 1  # this is a comment",
    "# comment on a whole line",
    "bar: 2",
    "baz: blah  # another comment",
    "some_bool: true",
    "some_implicit_null: # and another",
    "some_explicit_null: null",
  }, "\n"))
  eq({
    foo = 1,
    bar = 2,
    baz = "blah",
    some_bool = true,
    some_explicit_null = vim.NIL,
    some_implicit_null = vim.NIL, -- TODO: needed?
  }, result)
end

-- NOTE: a bit different indent, but treesitter one should be better?
T["should parse block strings"] = function()
  local result = yaml.loads [[
foo: |
  # a comment here should not be ignored!
  ls -lh
    # extra indent should not be ignored either!
    ]]
  eq({
    foo = table.concat(
      { "# a comment here should not be ignored!", "  ls -lh", "    # extra indent should not be ignored either!" },
      "\n"
    ),
  }, result)
end

T["should parse inline arrays"] = function()
  local result = yaml.loads(table.concat({
    "foo: [Foo, 'Bar', 1]",
  }, "\n"))
  eq({ foo = { "Foo", "Bar", 1 } }, result)
end

T["should parse inline mappings"] = function()
  local result = yaml.loads [[
foo: {bar: 1, baz: 'Baz'}
]]
  eq({ foo = { bar = 1, baz = "Baz" } }, result)
end

T["should parse nested inline arrays"] = function()
  local result = yaml.loads(table.concat({
    "foo: [Foo, ['Bar', 'Baz'], 1]",
  }, "\n"))
  eq({ foo = { "Foo", { "Bar", "Baz" }, 1 } }, result)
end

T["should parse array item strings with ':' in them"] = function()
  local result = yaml.loads [[
aliases:
 - "Research project: staged training"
sources:
 - https://example.com
]]
  eq({ aliases = { "Research project: staged training" }, sources = { "https://example.com" } }, result)
end

-- NOTE: invalid yaml for ts
-- T["should parse array item strings with '#' in them"] = function()
--   local result = yaml.loads [[
-- tags:
-- - #demo
-- ]]
--   eq({ tags = { "#demo" } }, result)
-- end

-- T["should parse array item strings that look like markdown links"] = function()
--   local result = yaml.loads [[
-- links:
-- - [Foo](bar)
-- ]]
--   eq({ links = { "[Foo](bar)" } }, result)
-- end

--- NOTE: old case is not yaml
T["should parse multi-line strings"] = function()
  --   local result = yaml.loads [[
  -- foo: 'this is the start of a string'
  --   # a comment here should not be ignored!
  --   'and this is the end of it'
  -- bar: 1
  -- ]]
  --
  local result = yaml.loads [[
foo: 'this is the start of a string
 and this is the end of it'
bar: 1
]]

  eq({
    foo = "this is the start of a string\n and this is the end of it",
    bar = 1,
  }, result)
end

return T
