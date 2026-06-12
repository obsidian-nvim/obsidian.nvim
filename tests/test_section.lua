local Section = require "obsidian.section"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["setext headings get anchors and ranges"] = function()
  local sections = Section.parse {
    "Title",
    "====",
    "",
    "Body",
    "",
    "Subtitle",
    "---",
    "More",
  }

  eq(3, #sections)
  eq("Title", sections[2].header)
  eq(1, sections[2].level)
  eq("#title", sections[2].anchor)
  eq({ start_row = 0, start_col = 0, end_row = 2, end_col = 0 }, sections[2].heading_range)
  eq({ start_row = 3, start_col = 0, end_row = 4, end_col = 0 }, sections[2].content_range)

  eq("Subtitle", sections[3].header)
  eq(2, sections[3].level)
  eq("#subtitle", sections[3].anchor)
  eq(sections[2], sections[3].parent)
  eq({ start_row = 0, start_col = 0, end_row = 8, end_col = 0 }, sections[2].range)
end

T["blocks attach to heading and paragraph sections"] = function()
  local _, blocks = Section.parse({
    "# Heading ^head",
    "",
    "Text ^para",
    "continued",
    "^standalone",
  }, { collect_blocks = true })

  eq("Heading ^head", blocks["^head"].section.header)
  eq({ start_row = 0, start_col = 0, end_row = 1, end_col = 0 }, blocks["^head"].section.heading_range)
  eq({ start_row = 2, start_col = 0, end_row = 5, end_col = 0 }, blocks["^para"].section.range)
  eq(blocks["^para"].section, blocks["^standalone"].section)
end

T["full ranges include nested descendants only"] = function()
  local sections = Section.parse {
    "# H1",
    "h1 text",
    "## H2",
    "h2 text",
    "### H3",
    "h3 text",
    "## H2b",
    "h2b text",
    "# H1b",
    "h1b text",
  }

  eq({ start_row = 0, start_col = 0, end_row = 8, end_col = 0 }, sections[2].range)
  eq({ start_row = 2, start_col = 0, end_row = 6, end_col = 0 }, sections[3].range)
  eq({ start_row = 4, start_col = 0, end_row = 6, end_col = 0 }, sections[4].range)
  eq({ start_row = 6, start_col = 0, end_row = 8, end_col = 0 }, sections[5].range)
  eq({ start_row = 8, start_col = 0, end_row = 10, end_col = 0 }, sections[6].range)
end

T["content ranges trim trailing blanks"] = function()
  local sections = Section.parse {
    "# H",
    "",
    "body",
    "",
    "",
    "## Next",
  }

  eq({ start_row = 2, start_col = 0, end_row = 3, end_col = 0 }, sections[2].content_range)
end

return T
