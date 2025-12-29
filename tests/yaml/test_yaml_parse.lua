local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set {
  parametrize = {
    { require "obsidian.yaml.yq" },
    { require "obsidian.yaml.treesitter" },
    { require "obsidian.yaml.lua" },
  },
}

T["should parse inline lists with quotes on items"] = function(yaml)
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

T["should parse inline lists without quotes on items"] = function(yaml)
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

T["should parse boolean field values"] = function(yaml)
  local data = yaml.loads "complete: false"
  eq(type(data), "table")
  eq(type(data.complete), "boolean")
end

-- TODO:
T["should parse implicit null values"] = function(yaml)
  local data = yaml.loads "tags: \ncomplete: false"
  eq(type(data), "table")
  eq(data.tags, vim.NIL)
  eq(data.complete, false)
end

-- TODO:
-- T["should parse explicit null values while trimming whitespace"] = function(yaml)
--   eq(vim.NIL, yaml.loads " null")
-- end

-- TODO:
-- T["should parse strings with escaped quotes"] = function(yaml)
--   eq([["foo"]], yaml.loads [["\"foo\""]])
-- end

-- TODO:
-- T["should parse simple non-nested mappings"] = function(yaml)
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

T["should parse booleans while trimming whitespace"] = function(yaml)
  eq(true, yaml.loads " true")
  eq(false, yaml.loads " false ")
end

T["should parse root-level scalars"] = function(yaml)
  eq("a string", yaml.loads "a string")
  eq(true, yaml.loads "true")
end

T["should parse mappings with spaces for keys"] = function(yaml)
  local result = yaml.loads(table.concat({
    "bar: 2",
    "modification date: Tuesday 26th March 2024 18:01:42",
  }, "\n"))
  eq({
    bar = 2,
    ["modification date"] = "Tuesday 26th March 2024 18:01:42",
  }, result)
end

T["should parse mappings with parens for keys"] = function(yaml)
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

T["should parse lists with or without extra indentation"] = function(yaml)
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

T["should parse a top-level list"] = function(yaml)
  local result = yaml.loads(table.concat({
    "- 1",
    "- 2",
    "# ignore this comment",
    "- 3",
  }, "\n"))
  eq({ 1, 2, 3 }, result)
end

T["should parse nested mapping"] = function(yaml)
  local result = yaml.loads [[
foo:
  bar: 1
  # ignore this comment
  baz: 2
    ]]
  eq({ foo = { bar = 1, baz = 2 } }, result)
end

-- TODO:
-- T["should ignore comments"] = function(yaml)
--   local result = yaml.loads(table.concat({
--     "foo: 1  # this is a comment",
--     "# comment on a whole line",
--     "bar: 2",
--     "baz: blah  # another comment",
--     "some_bool: true",
--     "some_implicit_null: # and another",
--     "some_explicit_null: null",
--   }, "\n"))
--   eq({
--     foo = 1,
--     bar = 2,
--     baz = "blah",
--     some_bool = true,
--     some_explicit_null = vim.NIL,
--     some_implicit_null = vim.NIL, -- TODO: needed?
--   }, result)
-- end

-- T["should parse block strings"] = function(yaml)
--   local result = yaml.loads [[
-- foo: |
--   # a comment here should not be ignored!
--   ls -lh
--     # extra indent should not be ignored either!]]
--   eq({
--     foo = table.concat(
--       { "# a comment here should not be ignored!", "ls -lh", "  # extra indent should not be ignored either!" },
--       "\n"
--     ),
--   }, result)
-- end

--- NOTE: https://yaml-multiline.info/
-- T["should parse multi-line strings"] = function(yaml)
--   --   local result = yaml.loads [[
--   -- foo: 'this is the start of a string'
--   --   # a comment here should not be ignored!
--   --   'and this is the end of it'
--   -- bar: 1
--   -- ]]
--   --
--   local result = yaml.loads [[
-- foo: 'this is the start of a string
--  and this is the end of it'
-- bar: 1
-- ]]
--
--   eq({
--     foo = "this is the start of a string and this is the end of it",
--     bar = 1,
--   }, result)
-- end

T["should parse inline arrays"] = function(yaml)
  local result = yaml.loads(table.concat({
    "foo: [Foo, 'Bar', 1]",
  }, "\n"))
  eq({ foo = { "Foo", "Bar", 1 } }, result)
end

T["should parse inline mappings"] = function(yaml)
  local result = yaml.loads [[
foo: {bar: 1, baz: 'Baz'}
]]
  eq({ foo = { bar = 1, baz = "Baz" } }, result)
end

T["should parse nested inline arrays"] = function(yaml)
  local result = yaml.loads(table.concat({
    "foo: [Foo, ['Bar', 'Baz'], 1]",
  }, "\n"))
  eq({ foo = { "Foo", { "Bar", "Baz" }, 1 } }, result)
end

T["should parse array item strings with ':' in them"] = function(yaml)
  local result = yaml.loads [[
aliases:
 - "Research project: staged training"
sources:
 - https://example.com
]]
  eq({ aliases = { "Research project: staged training" }, sources = { "https://example.com" } }, result)
end

-- NOTE: invalid yaml for ts
-- T["should parse array item strings with '#' in them"] = function(yaml)
--   local result = yaml.loads [[
-- tags:
-- - #demo
-- ]]
--   eq({ tags = { "#demo" } }, result)
-- end

-- T["should parse array item strings that look like markdown links"] = function(yaml)
--   local result = yaml.loads [[
-- links:
-- - [Foo](bar)
-- ]]
--   eq({ links = { "[Foo](bar)" } }, result)
-- end

return T
