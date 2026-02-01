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
    _GET_REF_TYPE = function(line_text, start_col, end_col)
      local search = require("obsidian.search")
      local refs = search.find_refs(line_text)  -- returns all refs in the line
      for _, ref in ipairs(refs) do
        if ref.start == start_col and ref["end"] == end_col then
          return ref.type  -- now refs have a .type field
        end
      end
      return nil
    end

    local Note = require("obsidian.note")
    local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
    _NOTE_BACKLINKS = note:backlinks({})
  ]]

  local backlinks = child.lua_get [[_NOTE_BACKLINKS]]
  local found_types = {}
  for _, m in ipairs(backlinks) do
    local r_type = child.lua_get(("_GET_REF_TYPE(%s, %s, %s)"):format(vim.fn.json_encode(m.text), m.start, m["end"]))
    if r_type then
      found_types[r_type] = true
    end
  end

  local expected = {
    "Wiki",
    "WikiWithAlias",
    "Markdown",
  }

  for _, t in ipairs(expected) do
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
