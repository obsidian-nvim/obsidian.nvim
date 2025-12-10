local yaml = require "obsidian.yaml.parser"

local parser = yaml.new { luanil = false }

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["should parse strings while trimming whitespace"] = function()
  eq("foo", parser:parse_string " foo")
end

T["should parse strings enclosed with double quotes"] = function()
  eq("foo", parser:parse_string [["foo"]])
end

T["should parse strings enclosed with single quotes"] = function()
  eq("foo", parser:parse_string [['foo']])
end

T["should parse strings with escaped quotes"] = function()
  eq([["foo"]], parser:parse_string [["\"foo\""]])
end

T["should parse numbers while trimming whitespace"] = function()
  eq(1, parser:parse_number " 1")
  eq(1.5, parser:parse_number " 1.5")
end

T["should error when trying to parse an invalid number"] = function()
  eq(
    false,
    pcall(function(str)
      return parser:parse_number(str)
    end, "foo")
  )
  eq(
    false,
    pcall(function(str)
      return parser:parse_number(str)
    end, "Nan")
  )
  eq(
    false,
    pcall(function()
      return parser:parse_number " 2025.5.6"
    end)
  )
end

T["should parse booleans while trimming whitespace"] = function()
  eq(true, parser:parse_boolean " true")
  eq(false, parser:parse_boolean " false ")
end

T["should error when trying to parse an invalid boolean"] = function()
  local ok, _ = pcall(function(str)
    return parser:parse_boolean(str)
  end, "foo")
  eq(false, ok)
end

T["should parse explicit null values while trimming whitespace"] = function()
  eq(vim.NIL, parser:parse_null " null")
end

T["should parse implicit null values"] = function()
  eq(vim.NIL, parser:parse_null " ")
end

T["should error when trying to parse an invalid null value"] = function()
  local ok, _ = pcall(function(str)
    return parser:parse_null(str)
  end, "foo")
  eq(false, ok)
end

T["should error when for invalid indentation"] = function()
  local ok, err = pcall(function(str)
    return parser:parse(str)
  end, " foo: 1\nbar: 2")
  eq(false, ok)
  assert(string.find(err, "indentation") ~= nil, err)
end

T["should parse root-level scalars"] = function()
  eq("a string", parser:parse "a string")
  eq(true, parser:parse "true")
end

T["should parse simple non-nested mappings"] = function()
  local result = parser:parse(table.concat({
    "foo: 1",
    "",
    "bar: 2",
    "baz: blah",
    "some_bool: true",
    "some_implicit_null:",
    "some_explicit_null: null",
  }, "\n"))
  eq({
    foo = 1,
    bar = 2,
    baz = "blah",
    some_bool = true,
    some_explicit_null = vim.NIL,
    some_implicit_null = vim.NIL,
  }, result)
end

T["should parse mappings with spaces for keys"] = function()
  local result = parser:parse(table.concat({
    "bar: 2",
    "modification date: Tuesday 26th March 2024 18:01:42",
  }, "\n"))
  eq({
    bar = 2,
    ["modification date"] = "Tuesday 26th March 2024 18:01:42",
  }, result)
end

T["should parse mappings with parens for keys"] = function()
  local result = parser:parse(table.concat({
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

T["should ignore comments"] = function()
  local result = parser:parse(table.concat({
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
    some_implicit_null = vim.NIL,
  }, result)
end

T["should parse lists with or without extra indentation"] = function()
  local result = parser:parse(table.concat({
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
  local result = parser:parse(table.concat({
    "- 1",
    "- 2",
    "# ignore this comment",
    "- 3",
  }, "\n"))
  eq({ 1, 2, 3 }, result)
end

T["should parse nested mapping"] = function()
  local result = parser:parse(table.concat({
    "foo:",
    "  bar: 1",
    "  # ignore this comment",
    "  baz: 2",
  }, "\n"))
  eq({ foo = { bar = 1, baz = 2 } }, result)
end

T["should parse block strings"] = function()
  local result = parser:parse(table.concat({
    "foo: |",
    "  # a comment here should not be ignored!",
    "  ls -lh",
    "    # extra indent should not be ignored either!",
  }, "\n"))
  eq({
    foo = table.concat(
      { "# a comment here should not be ignored!", "ls -lh", "  # extra indent should not be ignored either!" },
      "\n"
    ),
  }, result)
end

T["should parse multi-line strings"] = function()
  local result = parser:parse(table.concat({
    "foo: 'this is the start of a string'",
    "  # a comment here should not be ignored!",
    "  'and this is the end of it'",
    "bar: 1",
  }, "\n"))
  eq({
    foo = table.concat({ "this is the start of a string and this is the end of it" }, "\n"),
    bar = 1,
  }, result)
end

T["should parse inline arrays"] = function()
  local result = parser:parse(table.concat({
    "foo: [Foo, 'Bar', 1]",
  }, "\n"))
  eq({ foo = { "Foo", "Bar", 1 } }, result)
end

T["should parse nested inline arrays"] = function()
  local result = parser:parse(table.concat({
    "foo: [Foo, ['Bar', 'Baz'], 1]",
  }, "\n"))
  eq({ foo = { "Foo", { "Bar", "Baz" }, 1 } }, result)
end

T["should parse inline mappings"] = function()
  local result = parser:parse(table.concat({
    "foo: {bar: 1, baz: 'Baz'}",
  }, "\n"))
  eq({ foo = { bar = 1, baz = "Baz" } }, result)
end

T["should parse array item strings with ':' in them"] = function()
  local result = parser:parse(table.concat({
    "aliases:",
    ' - "Research project: staged training"',
    "sources:",
    " - https://example.com",
  }, "\n"))
  eq({ aliases = { "Research project: staged training" }, sources = { "https://example.com" } }, result)
end

T["should parse array item strings with '#' in them"] = function()
  local result = parser:parse(table.concat({
    "tags:",
    " - #demo",
  }, "\n"))
  eq({ tags = { "#demo" } }, result)
end

T["should parse array item strings that look like markdown links"] = function()
  local result = parser:parse(table.concat({
    "links:",
    " - [Foo](bar)",
  }, "\n"))
  eq({ links = { "[Foo](bar)" } }, result)
end

return T
