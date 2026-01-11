local M = require "obsidian.frontmatter"
local validator = require "obsidian.frontmatter.validator"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["validator"] = new_set()

T["validator"]["id"] = function()
  local v, err = validator.id("id", "path.md")
  eq(v, "id")
  eq(err, nil)
  v, err = validator.id(123, "path.md")
  eq(v, "123")
  eq(err, nil)
  v, err = validator.id({}, "path.md")
  eq(v, nil)
  eq(err, "Invalid id '{}' in frontmatter for path.md, Expected string or number found table")
end

T["validator"]["aliases"] = function()
  local v, err = validator.aliases({ "alias" }, "path.md")
  eq(v, { "alias" })
  eq(err, nil)
  v, err = validator.aliases("alias", "path.md")
  eq(v, { "alias" })
  eq(err, nil)
  v, err = validator.aliases({ {} }, "path.md")
  eq(v, nil)
  eq(err, "Invalid alias '{}' in frontmatter for path.md. Expected string, found table")
end

T["validator"]["tags"] = function()
  local v, err = validator.tags({ "alias" }, "path.md")
  eq(v, { "alias" })
  eq(err, nil)
  v, err = validator.tags("alias", "path.md")
  eq(v, { "alias" })
  eq(err, nil)
  v, err = validator.tags({ {} }, "path.md")
  eq(v, nil)
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

T["dump"]["dump attribute with null values"] = function()
  local lines = M.dump({ id = "id", aliases = {}, tags = {}, random = vim.NIL }, { "id", "aliases", "tags", "random" })

  local expected = {
    "---",
    "id: id",
    "aliases: []",
    "tags: []",
    "random:",
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
