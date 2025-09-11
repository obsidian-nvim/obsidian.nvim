local M = require "obsidian.frontmatter"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["dump"] = new_set()

T["dump"]["dump default frontmatter"] = function()
  local lines = M.dump(
    { id = "id", aliases = { "id", "alias" }, tags = { "tag1", "tag2" } },
    { "id", "aliases", "tags" }
  )
  local expected = {
    "---",
    "id: id",
    "aliases:",
    "  - id",
    "  - alias",
    "tags:",
    "  - tag1",
    "  - tag2",
    "---",
  }
  eq(expected, lines)
end

T["dump"]["dump random attributes"] = function()
  local lines = M.dump(
    { random = "stuff", id = "id", aliases = { "id", "alias" }, tags = { "tag1", "tag2" } },
    { "random", "id", "aliases", "tags" }
  )
  local expected = {
    "---",
    "random: stuff",
    "id: id",
    "aliases:",
    "  - id",
    "  - alias",
    "tags:",
    "  - tag1",
    "  - tag2",
    "---",
  }
  eq(expected, lines)
end

return T
