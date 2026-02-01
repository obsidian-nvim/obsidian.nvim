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
[[A]] [[A|Alias]] [A](A.md)
[A test](A.md#test) [Another](A.md#Section)
[[A#Section]] 
Multiple links: [[A]] [md](A.md#test) 
[[A#test]]
]==],
    root / "B.md"
  )
end

T["detects all RefTypes"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  child.lua [[
    local search = require("obsidian.search")
    local Note = require("obsidian.note")
    local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
    local backlinks = note:backlinks({})
    _FOUND_TYPES = {}
    for _, m in ipairs(backlinks) do
      local refs = search.find_refs(m.text)
      for _, ref in ipairs(refs) do
        local t = ref.ref_type or ref.type
        if t then
          _FOUND_TYPES[t] = true
        end
      end
    end
  ]]
  local found_types = child.lua_get [[_FOUND_TYPES]]
  local expected_types = { "Wiki", "WikiWithAlias", "Markdown" }
  for _, t in ipairs(expected_types) do
    eq(true, found_types[t] == true, "Missing ref type: " .. t)
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
  eq(3, #test_links)
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
  local found_multi = false
  for _, count in pairs(by_line) do
    if count > 1 then
      found_multi = true
      break
    end
  end
  assert(found_multi, "Expected multiple backlinks on a single line")
end

return T
