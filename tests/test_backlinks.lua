local MiniTest = require "mini.test"
local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function get_backlinks(opts_lua)
  return h.child_await(
    child,
    ([=[
      local Note = require("obsidian.note")
      local search = require("obsidian.search")
      local note = Note.new("A", {}, {}, Obsidian.dir / "A.md")
      search.find_backlinks_async(note, function(matches)
        done(matches)
      end, %s)
    ]=]):format(opts_lua),
    { desc = "backlinks" }
  )
end

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

T["detects note ref kinds"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  local refs = require "obsidian.parse.refs"
  local found_types = {}
  for _, m in ipairs(get_backlinks "{}") do
    for _, ref in ipairs(refs.extract(m.text)) do
      found_types[ref.kind] = true
    end
  end
  local expected = { "wiki", "markdown" }
  for _, t in ipairs(expected) do
    eq(true, found_types[t] == true, "Expected to find reference kind: " .. t)
  end
end

T["anchor filtering works"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  local section_links = get_backlinks [[{ anchor = "#Section" }]]
  local test_links = get_backlinks [[{ anchor = "#test" }]]
  eq(2, #section_links)
  eq(4, #test_links)
end

T["multiple links per line"] = function()
  local root = child.Obsidian.dir
  setup_vault(root)
  child.cmd("edit " .. tostring(root / "A.md"))
  local backlinks = get_backlinks "{}"
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
