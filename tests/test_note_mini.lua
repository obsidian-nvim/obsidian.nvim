local M = require "obsidian.note"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["should work from a file"] = function()
  local note = M.from_file_async "tests/fixtures/notes/foo.md"
  eq(note.id, "foo")
  eq(note.aliases[1], "foo")
  eq(note.aliases[2], "Foo")
  eq(note:fname(), "foo.md")
  eq(true, note.has_frontmatter)
  assert(#note.tags == 0)
end

return T
