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

T["frontmatter ranges preserve quoted source bytes and decoded values"] = function()
  local line = [[tags: ["a]b", 'it''s', '#É', 2026, "", null, false, '#'] # comment]]
  local occurrences = tags.extract { "---", line, "---" }
  eq(
    { "a]b", "it's", "É", "2026" },
    vim.tbl_map(function(item)
      return item.tag
    end, occurrences)
  )
  eq(
    { "a]b", "it''s", "É", "2026" },
    vim.tbl_map(function(item)
      return item.raw
    end, occurrences)
  )
  for _, occurrence in ipairs(occurrences) do
    eq(occurrence.source, "frontmatter")
    eq(occurrence.range.start_row, 1)
    eq(occurrence.range.end_row, 1)
    eq(line:sub(occurrence.range.start_col + 1, occurrence.range.end_col), occurrence.raw)
  end
  eq(2, occurrences[3].range.end_col - occurrences[3].range.start_col)
end

T["frontmatter handles unindented sequences and physical blank lines"] = function()
  local occurrences = tags.extract {
    "---",
    "",
    "tags:",
    "",
    "- One",
    "# comment",
    "- '#Two'",
    "",
    "- One",
    "---",
  }
  eq(3, #occurrences)
  eq(Range.new(4, 2, 4, 5), occurrences[1].range)
  eq(Range.new(6, 4, 6, 7), occurrences[2].range)
  eq(Range.new(8, 2, 8, 5), occurrences[3].range)
end

T["frontmatter only uses the tags scalar or direct sequence items"] = function()
  local occurrences = tags.extract {
    "---",
    "aliases: [NotATag]",
    "metadata:",
    "  tags: Nested",
    "tags: [One, [Nested], {key: Mapped}, Two]",
    "---",
  }
  eq(
    { "One", "Two" },
    vim.tbl_map(function(item)
      return item.tag
    end, occurrences)
  )
  eq({}, tags.extract { "---", "tags: {key: NotATag}", "---" })
  eq({}, tags.extract { "---", "tags: |", "  Multiple", "  lines", "---" })
end

T["frontmatter supports scalar tags and ignores invalid YAML without hiding body tags"] = function()
  local occurrences = tags.extract { "---", "tags: '#One'", "---" }
  eq(1, #occurrences)
  eq("One", occurrences[1].tag)
  eq(Range.new(1, 8, 1, 11), occurrences[1].range)

  occurrences = tags.extract { "---", "tags: [One]", "broken: {", "---", "#Visible" }
  eq(1, #occurrences)
  eq("Visible", occurrences[1].tag)
  eq("inline", occurrences[1].source)
  eq({}, tags.extract { "---", "tags: One" })
  eq({}, tags.extract { "---", "---" })
end

T["frontmatter reuses note elements without reparsing or mutating lexical ranges"] = function()
  local yaml = require "obsidian.yaml"
  local Note = require "obsidian.note"
  local lines = { "---", "tags: ['#One', 'Two']", "---", "#Visible" }
  local note = Note.from_lines(lines)
  local before = vim.deepcopy(note.frontmatter_elements)
  local expected = tags.extract(lines)
  local loads = yaml.loads
  yaml.loads = function()
    error "frontmatter must not be reparsed"
  end
  local ok, occurrences = pcall(tags.extract, lines, {
    frontmatter_end_line = note.frontmatter_end_line,
    frontmatter_elements = note.frontmatter_elements,
  })
  yaml.loads = loads
  eq(true, ok)
  eq(expected, occurrences)
  eq(before, note.frontmatter_elements)
  eq(Range.new(1, 7, 1, 13), note.frontmatter_elements[1].range)

  -- An empty parse result is authoritative, not a request to retry the parser.
  occurrences = tags.extract(lines, { frontmatter_end_line = 3, frontmatter_elements = {} })
  eq(1, #occurrences)
  eq("Visible", occurrences[1].tag)
end

return T
