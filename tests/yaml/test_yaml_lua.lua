local yaml = require "obsidian.yaml.lua"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

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
  eq(data.tags, nil)
  eq(data.complete, false)
end

return T
