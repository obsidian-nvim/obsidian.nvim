local MiniTest = require "mini.test"
local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()
local function setup_vault(root)
  h.write(
    "# A\n" .. "## Section\n" .. "Paragraph with block ^block-id\n" .. "==highlighted text==\n" .. "## test\n",
    root / "A.md"
  )
  h.write(
    [==[
[[A]] [[A|Alias]] [A](A.md) [[B]] [false posititve](B.md)
[A test](A.md#test) [Another](A.md#Section)
[[A#Section]] 
Multiple links: [[A]] [md](A.md#test) [md](A.md#test) 
[[A#test]]
]==],
    root / "B.md"
  )
end

T["detects all RefTypes"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  local found_types = child.lua [[
    local search = require("obsidian.search")
    local Note = require("obsidian.note")
    local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
    local backlinks = note:backlinks({})
    local found = {}
    for _, m in ipairs(backlinks) do
      local refs = search.find_refs(m.text)
      for _, ref in ipairs(refs) do
        local ref_start, ref_end, ref_type = unpack(ref)
        local t = ref_type 
        if t then 
          found[t] = true 
        end
      end
    end
    return found
  ]]
  local expected = { "Wiki", "WikiWithAlias", "Markdown" }
  for _, t in ipairs(expected) do
    eq(true, found_types[t] == true, "Expected to find reference type: " .. t)
  end
end

T["anchor filtering works"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
    local Note = require("obsidian.note")
    local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
    _NOTE_SECTION = note:backlinks({ anchor = "#Section" })
    _NOTE_TEST    = note:backlinks({ anchor = "#test" })
  ]]
  local section_links = child.lua_get [[_NOTE_SECTION]]
  local test_links = child.lua_get [[_NOTE_TEST]]
  eq(2, #section_links)
  eq(4, #test_links)
end

T["multiple links per line"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
    local Note = require("obsidian.note")
    local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
    _NOTE_BACKLINKS = note:backlinks({})
  ]]
  local backlinks = child.lua_get [[_NOTE_BACKLINKS]]
  local by_line = {}
  for _, m in ipairs(backlinks) do
    local l = m.line
    by_line[l] = (by_line[l] or 0) + 1
  end
  eq(by_line[1], 3)
  eq(by_line[2], 2)
  eq(by_line[3], 1)
  eq(by_line[4], 3)
  eq(by_line[5], 1)
end

return T
