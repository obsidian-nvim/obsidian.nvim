local backlinks = require "obsidian.index.backlinks"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local notes = {
  ["/vault/A.md"] = {},
  ["/vault/Dir/B.md"] = {},
  ["/vault/Src.md"] = {
    links_out = {
      { target = "A", line = 3, raw = "[[A]]" },
      { target = "Dir/B.md", line = 1, raw = "[B](Dir/B.md)" },
      { target = "https://example.com", line = 5, raw = "[x](https://example.com)" },
    },
  },
}

T["resolve matches basename and relative path"] = function()
  eq({ "/vault/A.md" }, backlinks.resolve("A", notes, { root = "/vault" }))
  eq({ "/vault/Dir/B.md" }, backlinks.resolve("Dir/B.md", notes, { root = "/vault" }))
end

T["resolve ignores URIs"] = function()
  eq({}, backlinks.resolve("https://example.com", notes, { root = "/vault" }))
end

T["build_for returns sorted backlinks"] = function()
  local out = backlinks.build_for("/vault/A.md", notes, { root = "/vault" })
  eq(1, #out)
  eq("/vault/Src.md", out[1].source)
  eq(3, out[1].link.line)
end

return T
