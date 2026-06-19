local tags = require "obsidian.index.tags"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["collect lowercases tags"] = function()
  local idx = tags.collect {
    ["/v/a.md"] = { tags = { "Foo", "foo/bar" } },
    ["/v/b.md"] = { tags = { "foo" } },
  }

  eq({ "/v/a.md", "/v/b.md" }, idx.foo)
  eq({ "/v/a.md" }, idx["foo/bar"])
end

T["matching returns nested tags"] = function()
  local idx = { foo = {}, ["foo/bar"] = {}, other = {} }
  eq({ "foo", "foo/bar" }, tags.matching(idx, "#foo"))
end

T["paths_for_tags deduplicates"] = function()
  local idx = { foo = { "b", "a" }, bar = { "a" } }
  eq({ "a", "b" }, tags.paths_for_tags(idx, { "foo", "bar" }))
end

return T
