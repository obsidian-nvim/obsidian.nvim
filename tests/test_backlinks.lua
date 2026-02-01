local MiniTest = require "mini.test"
local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function has(backlinks, opts)
  for _, m in ipairs(backlinks) do
    if (not opts.type or m.ref.type == opts.type) and (not opts.anchor or m.ref.anchor == opts.anchor) then
      return true
    end
  end
  return false
end

T["detects all RefTypes"] = function()
  local root = child.Obsidian.dir
  h.write(
    "# A\n" .. "## Section\n" .. "Paragraph with block ^block-id\n" .. "==highlighted text==\n" .. "## test\n",
    root / "A.md"
  )
  h.write(
    [==[
[[A]] [[A|Alias]] [A](A.md)
[A test](A.md#test) [Another](A.md#Section)
https://example.com/A.md file:///vault/A.md mailto:test@example.com
#A ^block-id ==highlighted text==
[[A#Section]] [[A#^block-id]]
Multiple links: [[A]] [md](A.md#test) [[A#Section]]
]==],
    root / "B.md"
  )
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
local Path = require("obsidian.path")
local Note = require("obsidian.note")
local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
_NOTE_BACKLINKS = note:backlinks({})
]]
  local backlinks = child.lua_get [[_NOTE_BACKLINKS]]
  local expected = {
    "Wiki",
    "WikiWithAlias",
    "Markdown",
    "NakedUrl",
    "FileUrl",
    "MailtoUrl",
    "Tag",
    "BlockID",
    "Highlight",
    "HeaderLink",
    "BlockLink",
  }
  for _, t in ipairs(expected) do
    eq(true, has(backlinks, { type = t }), "Missing ref type: " .. t)
  end
  child.lua [[_NOTE_BACKLINKS = nil]]
end

T["anchor filtering works"] = function()
  local root = child.Obsidian.dir
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
local Path = require("obsidian.path")
local Note = require("obsidian.note")
local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
_NOTE_SECTION = note:backlinks({ anchor = "Section" })
_NOTE_TEST    = note:backlinks({ anchor = "test" })
]]
  local section_links = child.lua_get [[_NOTE_SECTION]]
  local test_links = child.lua_get [[_NOTE_TEST]]
  eq(3, #section_links)
  for _, m in ipairs(section_links) do
    eq("Section", m.ref.anchor)
    assert(
      m.ref.type == "HeaderLink" or m.ref.type == "Markdown",
      "Unexpected ref type for Section anchor: " .. tostring(m.ref.type)
    )
  end
  eq(2, #test_links)
  for _, m in ipairs(test_links) do
    eq("test", m.ref.anchor)
    eq("Markdown", m.ref.type)
  end
  child.lua [[_NOTE_SECTION = nil _NOTE_TEST = nil]]
end

T["multiple links per line"] = function()
  local root = child.Obsidian.dir
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
local Path = require("obsidian.path")
local Note = require("obsidian.note")
local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
_NOTE_BACKLINKS = note:backlinks({})
]]

  local backlinks = child.lua_get [[_NOTE_BACKLINKS]]
  local by_line = {}
  for _, m in ipairs(backlinks) do
    by_line[m.lnum] = (by_line[m.lnum] or 0) + 1
  end
  local found_multi = false
  for _, count in pairs(by_line) do
    if count > 1 then
      found_multi = true
      break
    end
  end
  assert(found_multi, "Expected multiple backlinks on a single line")
  child.lua [[_NOTE_BACKLINKS = nil]]
end

return T
