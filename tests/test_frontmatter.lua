local M = require "obsidian.frontmatter"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["validater"] = new_set()

T["validater"]["id"] = function()
  local v, err = M._validater.id("id", "path.md")
  eq(v, "id")
  eq(nil, err)
  v, err = M._validater.id(123, "path.md")
  eq(v, "123")
  eq(nil, err)
  v, err = M._validater.id({}, "path.md")
  eq(err, "Invalid id '{}' in frontmatter for path.md, Expected string or number found table")
end

T["validater"]["aliases"] = function()
  local v, err = M._validater.aliases({ "alias" }, "path.md")
  eq(v, { "alias" })
  eq(nil, err)
  v, err = M._validater.aliases("alias", "path.md")
  eq(v, { "alias" })
  eq(nil, err)
  v, err = M._validater.aliases({ {} }, "path.md")
  eq(err, "Invalid alias '{}' in frontmatter for path.md. Expected string, found table")
end

T["validater"]["tags"] = function()
  local v, err = M._validater.tags({ "alias" }, "path.md")
  eq(v, { "alias" })
  eq(nil, err)
  v, err = M._validater.tags("alias", "path.md")
  eq(v, { "alias" })
  eq(nil, err)
  v, err = M._validater.tags({ {} }, "path.md")
  eq(err, "Invalid tag '{}' found in frontmatter for path.md. Expected string, found table")
end

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

T["dump"]["dump with custom order function"] = function()
  local lines = M.dump(
    { random = "stuff", id = "id", aliases = { "id", "alias" }, tags = { "tag1", "tag2" } },
    function(a, b)
      local a_idx, b_idx = nil, nil
      for i, k in ipairs { "id", "aliases", "tags" } do
        if a == k then
          a_idx = i
        end
        if b == k then
          b_idx = i
        end
      end
      if a_idx and b_idx then
        return a_idx < b_idx
      elseif a_idx then
        return true
      elseif b_idx then
        return false
      else
        return a < b
      end
    end
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
    "random: stuff",
    "---",
  }
  eq(expected, lines)
end

T["parse"] = function()
  local lines = {
    "id: id",
    "aliases:",
    "  - id",
    "  - alias",
    "tags:",
    "  - tag1",
    "  - tag2",
    "random: stuff",
  }
  local t, metadata = M.parse(lines, "")
  eq(t.id, "id")
  eq(t.aliases, { "id", "alias" })
  eq(t.tags, { "tag1", "tag2" })
  eq(metadata, { random = "stuff" })
end

return T
