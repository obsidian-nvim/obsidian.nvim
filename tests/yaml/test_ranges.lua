local yaml = require "obsidian.yaml"
local Parser = require "obsidian.yaml.parser"
local Range = require "obsidian.range"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local function expect_element(element, path, value, range)
  eq(element, { kind = "scalar", path = path, value = value, range = range })
end

local function source_text(lines, range)
  if range.start_row == range.end_row then
    return lines[range.start_row + 1]:sub(range.start_col + 1, range.end_col)
  end
  local parts = { lines[range.start_row + 1]:sub(range.start_col + 1) }
  for row = range.start_row + 1, range.end_row - 1 do
    parts[#parts + 1] = lines[row + 1]
  end
  parts[#parts + 1] = lines[range.end_row + 1]:sub(1, range.end_col)
  return table.concat(parts, "\n")
end

T["preserves physical rows, base indentation, and document origin"] = function()
  local lines = { "", "# comment", "  tags:", "", "    - café", "    - 'café' # comment", "" }
  local before = vim.deepcopy(lines)
  local value, order, elements = yaml.loads(lines, { base_row = 7 })
  eq(value, { tags = { "café", "café" } })
  eq(order, { "tags" })
  eq(#elements, 2)
  expect_element(elements[1], { "tags", 1 }, "café", Range.new(11, 6, 11, 11))
  expect_element(elements[2], { "tags", 2 }, "café", Range.new(12, 6, 12, 13))
  eq(lines, before)
  local _, _, crlf = yaml.loads(table.concat(lines, "\r\n"), { base_row = 7 })
  eq(crlf, elements)
end

T["keeps quoted lexemes and byte columns for repeated flow items"] = function()
  local line = [[tags: [é, "", 'it''s', "a\"b", "a # b", é] # comment]]
  local value, _, elements = yaml.loads { line }
  eq(value.tags, { "é", "", "it's", 'a"b', "a # b", "é" })
  local raw = { "é", '""', "'it''s'", '"a\\"b"', '"a # b"', "é" }
  eq(#elements, #raw)
  for i, element in ipairs(elements) do
    eq(element.path, { "tags", i })
    eq(source_text({ line }, element.range), raw[i])
  end
  eq(elements[1].range, Range.new(0, 7, 0, 9))
  eq(elements[2].range.start_col, 11)
end

T["records nested paths without searching decoded values"] = function()
  local lines = {
    "outer:",
    "",
    "  # comment",
    "  values: [one, [two, [three]], {key: four}]",
    "",
    "  flag: false",
    "tail: 1",
  }
  local value, _, elements = yaml.loads(lines)
  eq(value, { outer = { values = { "one", { "two", { "three" } }, { key = "four" } }, flag = false }, tail = 1 })
  local paths = {
    { "outer", "values", 1 },
    { "outer", "values", 2, 1 },
    { "outer", "values", 2, 2, 1 },
    { "outer", "values", 3, "key" },
    { "outer", "flag" },
    { "tail" },
  }
  local raw = { "one", "two", "three", "four", "false", "1" }
  eq(#elements, #paths)
  for i, element in ipairs(elements) do
    eq(element.path, paths[i])
    eq(source_text(lines, element.range), raw[i])
  end
end

T["preserves offsets around whitespace and nested flow delimiters"] = function()
  local line = [[data: { list: [ ["é"] , { key: 'a' } , b ] , empty: { } }]]
  local value, _, elements = yaml.loads { line }
  eq(value, { data = { list = { { "é" }, { key = "a" }, "b" }, empty = {} } })
  eq(#elements, 3)
  eq(elements[1].path, { "data", "list", 1, 1 })
  eq(elements[2].path, { "data", "list", 2, "key" })
  eq(elements[3].path, { "data", "list", 3 })
  for i, raw in ipairs { '"é"', "'a'", "b" } do
    eq(source_text({ line }, elements[i].range), raw)
  end
end

T["records root and block sequence paths"] = function()
  local _, _, root = yaml.loads { "- one", "", "- two" }
  expect_element(root[1], { 1 }, "one", Range.new(0, 2, 0, 5))
  expect_element(root[2], { 2 }, "two", Range.new(2, 2, 2, 5))
  local _, _, scalar = yaml.loads "'quoted'"
  expect_element(scalar[1], {}, "quoted", Range.new(0, 0, 0, 8))
  local _, _, nested = yaml.loads { "items:", "  - name: one", "  - name: two" }
  eq(nested[1].path, { "items", 1, "name" })
  eq(nested[1].range, Range.new(1, 10, 1, 13))
  eq(nested[2].path, { "items", 2, "name" })
end

T["represents implicit nulls with empty ranges"] = function()
  local _, _, elements = yaml.loads { "absent:", "tags:", "  -", "  - null", "  - ~" }
  expect_element(elements[1], { "absent" }, vim.NIL, Range.new(0, 7, 0, 7))
  expect_element(elements[2], { "tags", 1 }, vim.NIL, Range.new(2, 3, 2, 3))
  expect_element(elements[3], { "tags", 2 }, vim.NIL, Range.new(3, 4, 3, 8))
  expect_element(elements[4], { "tags", 3 }, vim.NIL, Range.new(4, 4, 4, 5))
end

T["retains blank lines and a single extent for literal block scalars"] = function()
  local lines = { "body: |", "  first  ", "", "  # literal", "  last", "next: value" }
  local value, _, elements = yaml.loads(lines)
  eq(value, { body = "first  \n\n# literal\nlast", next = "value" })
  expect_element(elements[1], { "body" }, value.body, Range.new(0, 6, 4, 6))
  eq(source_text(lines, elements[1].range), "|\n  first  \n\n  # literal\n  last")
  eq(elements[2].path, { "next" })
end

T["merges plain multiline scalar occurrences"] = function()
  local lines = { "body: first", "  # comment", "  second # comment", "next: value" }
  local value, _, elements = yaml.loads(lines)
  eq(value.body, "first second")
  eq(#elements, 2)
  expect_element(elements[1], { "body" }, "first second", Range.new(0, 6, 2, 8))
end

T["keeps plain scalar continuation across physical blank lines"] = function()
  local lines = { "body: first", "", "  second", "", "# comment", "  third", "next: value" }
  local value, _, elements = yaml.loads(lines)
  eq(value.body, "first second third")
  eq(#elements, 2)
  expect_element(elements[1], { "body" }, value.body, Range.new(0, 6, 5, 7))
end

T["keeps source indices when luanil omits decoded sequence items"] = function()
  local parser = Parser.new { luanil = true }
  local _, _, elements = parser:parse { "tags: [null, one]" }
  eq(#elements, 2)
  expect_element(elements[1], { "tags", 1 }, nil, Range.new(0, 7, 0, 11))
  expect_element(elements[2], { "tags", 2 }, "one", Range.new(0, 13, 0, 16))
end

T["resets source state across parser reuse and errors"] = function()
  local parser = Parser.new()
  local _, _, first = parser:parse { "tags: [one]" }
  eq(pcall(parser.parse, parser, { "tags: {broken" }), false)
  local _, _, second = parser:parse({ "other: two" }, { base_row = 3 })
  eq(#first, 1)
  expect_element(first[1], { "tags", 1 }, "one", Range.new(0, 7, 0, 10))
  expect_element(second[1], { "other" }, "two", Range.new(3, 7, 3, 10))
  local _, _, empty = parser:parse { "", "# comment", "" }
  eq(empty, {})
end

T["reports physical line numbers after blank lines"] = function()
  local ok, err = pcall(yaml.loads, "\nfoo: 1\n\n  bad: 2")
  eq(ok, false)
  eq(err:match "%[line=4%]" ~= nil, true)
end

T["exposes frontmatter occurrences before validation"] = function()
  local Frontmatter = require "obsidian.frontmatter"
  local info, _, errors, elements = Frontmatter.parse({ "tags: [2026, 'é']" }, "note.md", { base_row = 1 })
  eq(info.tags, { "2026", "é" })
  eq(errors, {})
  expect_element(elements[1], { "tags", 1 }, 2026, Range.new(1, 7, 1, 11))
  expect_element(elements[2], { "tags", 2 }, "é", Range.new(1, 13, 1, 17))
end

T["stores note frontmatter ranges in document coordinates"] = function()
  local Note = require "obsidian.note"
  local note = Note.from_lines { "---", "", "tags:", "  - 'é'", "body: |", "  text  ", "---", "# Heading" }
  local elements = note.frontmatter_elements
  expect_element(elements[1], { "tags", 1 }, "é", Range.new(3, 4, 3, 8))
  expect_element(elements[2], { "body" }, "text  ", Range.new(4, 6, 5, 8))
end

return T
