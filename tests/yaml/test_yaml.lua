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

T["loads"]["should parse wikilinks as strings"] = function()
  local data = yaml.loads "a: [[note]]"
  eq(type(data), "table")
  eq(data.a, "[[note]]")

  data = yaml.loads "a: [[note|alias]]"
  eq(data.a, "[[note|alias]]")

  data = yaml.loads "a: [[note#section]]"
  eq(data.a, "[[note#section]]")
end

T["loads"]["should parse wikilinks in arrays as strings"] = function()
  local data = yaml.loads "a:\n  - [[note]]"
  eq(type(data), "table")
  eq(type(data.a), "table")
  eq(data.a[1], "[[note]]")

  data = yaml.loads "a:\n  - [[note|alias]]\n  - [[other]]"
  eq(data.a[1], "[[note|alias]]")
  eq(data.a[2], "[[other]]")
end

T["dump"] = T["dump"] or new_set()

T["dump"]["should quote wikilinks in scalar values"] = function()
  eq(yaml.dumps { a = "[[note]]" }, 'a: "[[note]]"')
  eq(yaml.dumps { a = "[[note|alias]]" }, 'a: "[[note|alias]]"')
  eq(yaml.dumps { a = "[[note#section]]" }, 'a: "[[note#section]]"')
end

T["dump"]["should quote wikilinks in arrays"] = function()
  eq(yaml.dumps { a = { "[[note]]" } }, 'a:\n  - "[[note]]"')
  eq(yaml.dumps { a = { "[[note|alias]]", "[[other]]" } }, 'a:\n  - "[[note|alias]]"\n  - "[[other]]"')
end

T["roundtrip"] = new_set()

T["roundtrip"]["should preserve wikilinks in scalar values"] = function()
  local original = "a: [[note]]"
  local loaded = yaml.loads(original)
  local dumped = yaml.dumps(loaded)
  local reloaded = yaml.loads(dumped)
  eq(reloaded.a, "[[note]]")
end

T["roundtrip"]["should preserve wikilinks in arrays"] = function()
  local original = "a:\n  - [[note]]\n  - [[other]]"
  local loaded = yaml.loads(original)
  local dumped = yaml.dumps(loaded)
  local reloaded = yaml.loads(dumped)
  eq(reloaded.a[1], "[[note]]")
  eq(reloaded.a[2], "[[other]]")
end

T["roundtrip"]["should preserve multiline strings"] = function()
  local original = "description: |\n  Line 1\n  Line 2"
  local loaded = yaml.loads(original)
  eq(loaded.description, "Line 1\nLine 2")
  local dumped = yaml.dumps(loaded)
  local reloaded = yaml.loads(dumped)
  eq(reloaded.description, "Line 1\nLine 2")
end

return T
