local yaml = require "obsidian.yaml"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["dump"] = new_set()

T["dump"]["should dump numbers"] = function()
  eq(yaml.dumps(1), "1")
end

T["dump"]["should dump strings"] = function()
  eq(yaml.dumps "hi there", "hi there")
  eq(yaml.dumps "hi it's me", "hi it's me")
  eq(yaml.dumps { foo = "bar" }, [[foo: bar]])
end

T["dump"]["should dump strings with a single quote without quoting"] = function()
  eq(yaml.dumps "hi it's me", "hi it's me")
end

T["dump"]["should dump table with string values"] = function()
  eq(yaml.dumps { foo = "bar" }, [[foo: bar]])
end

T["dump"]["should dump arrays with string values"] = function()
  eq(yaml.dumps { "foo", "bar" }, "- foo\n- bar")
end

T["dump"]["should dump arrays with number values"] = function()
  eq(yaml.dumps { 1, 2 }, "- 1\n- 2")
end

T["dump"]["should dump arrays with simple table values"] = function()
  eq(yaml.dumps { { a = 1 }, { b = 2 } }, "- a: 1\n- b: 2")
end

T["dump"]["should dump tables with string values"] = function()
  eq(yaml.dumps { a = "foo", b = "bar" }, "a: foo\nb: bar")
end

T["dump"]["should dump tables with number values"] = function()
  eq(yaml.dumps { a = 1, b = 2 }, "a: 1\nb: 2")
end

T["dump"]["should dump tables with array values"] = function()
  eq(yaml.dumps { a = { "foo" }, b = { "bar" } }, "a:\n  - foo\nb:\n  - bar")
end

T["dump"]["should dump tables with empty array"] = function()
  eq(yaml.dumps { a = {} }, "a: []")
end

T["dump"]["should quote empty strings or strings with just whitespace"] = function()
  eq(yaml.dumps { a = "" }, 'a: ""')
  eq(yaml.dumps { a = " " }, 'a: " "')
end

T["dump"]["should not quote date-like strings"] = function()
  eq(yaml.dumps { a = "2025.5.6" }, "a: 2025.5.6")
  eq(yaml.dumps { a = "2023_11_10 13:26" }, "a: 2023_11_10 13:26")
end

T["dump"]["should otherwise quote strings with a colon followed by whitespace"] = function()
  eq(yaml.dumps { a = "2023: a letter" }, [[a: "2023: a letter"]])
end

T["dump"]["should quote strings that start with special characters"] = function()
  eq(yaml.dumps { a = "& aaa" }, [[a: "& aaa"]])
  eq(yaml.dumps { a = "! aaa" }, [[a: "! aaa"]])
  eq(yaml.dumps { a = "- aaa" }, [[a: "- aaa"]])
  eq(yaml.dumps { a = "{ aaa" }, [[a: "{ aaa"]])
  eq(yaml.dumps { a = "[ aaa" }, [[a: "[ aaa"]])
  eq(yaml.dumps { a = "'aaa'" }, [[a: "'aaa'"]])
  eq(yaml.dumps { a = '"aaa"' }, [[a: "\"aaa\""]])
end

T["dump"]["should not unnecessarily escape double quotes in strings"] = function()
  eq(yaml.dumps { a = 'his name is "Winny the Poo"' }, 'a: his name is "Winny the Poo"')
end

T["loads"] = new_set()

T["loads"]["should parse inline lists with quotes on items"] = function()
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

T["loads"]["should parse inline lists without quotes on items"] = function()
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

T["loads"]["should parse boolean field values"] = function()
  local data = yaml.loads "complete: false"
  eq(type(data), "table")
  eq(type(data.complete), "boolean")
end

T["loads"]["should parse implicit null values"] = function()
  local data = yaml.loads "tags: \ncomplete: false"
  eq(type(data), "table")
  eq(data.tags, vim.NIL)
  eq(data.complete, false)
end

return T
