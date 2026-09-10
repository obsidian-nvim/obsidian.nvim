local Range = require "obsidian.range"
local tags = require "obsidian.tag"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["normalize strips a hash and ignores case"] = function()
  eq("work/lua", tags.normalize "#WORK/Lua")
  eq(tags.normalize "#Ärende", tags.normalize "ärende")
end

T["matches exact, subtree, and prefix modes"] = function()
  eq(true, tags.matches("Work/Lua", "#work", "subtree"))
  eq(false, tags.matches("worker", "work", "subtree"))
  eq(false, tags.matches("work/lua", "work", "exact"))
  eq(true, tags.matches("Worker", "work", "prefix"))
end

T["extract handles frontmatter forms and Markdown exclusions"] = function()
  local occurrences = tags.extract {
    "---",
    "tags: [One, 'Two']",
    "---",
    "`#InlineCode` #Visible",
    "~~~lua",
    "#Fenced",
    "~~~",
  }

  eq(
    { "One", "Two", "Visible" },
    vim.tbl_map(function(occurrence)
      return occurrence.tag
    end, occurrences)
  )
  eq(Range.new(1, 7, 1, 10), occurrences[1].range)
  eq(Range.new(1, 13, 1, 16), occurrences[2].range)
  eq(Range.new(3, 14, 3, 22), occurrences[3].range)
end

return T
