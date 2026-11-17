local Fuzz = dofile "tests/fuzz/helpers.lua"
local Document = require "obsidian.parse.document"
local Pos = require "obsidian.pos"
local Range = require "obsidian.range"
local refs = require "obsidian.parse.refs"
local tags = require "obsidian.parse.tags"

local T = MiniTest.new_set()

local function check_line_matches(line, matches, row, kind)
  local last_end = 0
  for _, match in ipairs(matches) do
    local range = match.range
    assert(range.start_row == row and range.end_row == row, "match must be on the input row")
    assert(range.start_col >= last_end and range.start_col < range.end_col, "matches must be ordered and disjoint")
    assert(range.end_col <= #line, "match exceeds the input line")
    assert(match.raw == line:sub(range.start_col + 1, range.end_col), "raw must match source bytes")
    if kind == "tag" then
      assert(match.tag == match.raw:sub(2), "tag must exclude the hash")
    end
    last_end = range.end_col
  end
end

local function check_range(lines, range)
  local count = #lines
  assert(range.start_row >= 0 and range.start_row <= count, "start row outside document")
  assert(range.end_row >= 0 and range.end_row <= count, "end row outside document")
  assert(Pos.compare(Range.start_pos(range), Range.end_pos(range)) <= 0, "reversed range")
  for _, endpoint in ipairs {
    { range.start_row, range.start_col },
    { range.end_row, range.end_col },
  } do
    local row, col = endpoint[1], endpoint[2]
    assert(col >= 0 and col <= (lines[row + 1] and #lines[row + 1] or 0), "column outside document")
  end
end

T["reference ranges and raw text"] = function()
  Fuzz.run("refs", 0, function(rng)
    return rng:line()
  end, function(line)
    for _, lexical in ipairs { false, true } do
      check_line_matches(line, refs.extract(line, { row = 3, lexical = lexical }), 3)
    end
  end)
end

T["tag ranges and raw text"] = function()
  Fuzz.run("tags", 101, function(rng)
    return rng:line()
  end, function(line)
    for _, lexical in ipairs { false, true } do
      check_line_matches(line, tags.extract(line, { row = 3, lexical = lexical }), 3, "tag")
    end
  end)
end

T["document regions stay inside the source snapshot"] = function()
  Fuzz.run("document", 202, function(rng)
    return rng:document()
  end, function(lines)
    local doc = Document.parse(lines)
    assert(vim.deep_equal(doc.lines, lines), "parsing must preserve source lines")
    assert(doc:body_start_row() >= 0 and doc:body_start_row() <= #lines, "invalid body start")
    local previous
    for _, region in ipairs(doc.regions) do
      check_range(lines, region.range)
      if previous then
        assert(Pos.compare(Range.start_pos(previous), Range.start_pos(region.range)) <= 0, "unsorted regions")
      end
      for _, field in ipairs { "opener_range", "closer_range", "body_range" } do
        local subrange = region[field]
        if subrange then
          check_range(lines, subrange)
          assert(Range.contains_range(region.range, subrange), field .. " outside region")
        end
      end
      previous = region.range
    end
  end)
end

T["inline code and fenced code suppress references and tags"] = function()
  Fuzz.run("exclusions", 303, function(rng)
    local parts = {}
    for _ = 1, rng:int(4) do
      parts[#parts + 1] = rng:pick { "note", "hello-world", "你好", "mañana", "folder/note" }
    end
    return table.concat(parts, "-")
  end, function(name)
    local content = "[[" .. name .. "]] #tag"
    local line = "`" .. content .. "`"
    assert(#refs.extract(line) == 0 and #tags.extract(line) == 0, "inline code leaked a match")
    local lines = { "```", content, "```" }
    local doc = Document.parse(lines)
    local region = assert(doc.regions[1], "missing fenced-code region")
    assert(region.kind == "fenced_code", "expected fenced code")
    local found = 0
    for _, matches in ipairs { refs.extract(content, { lexical = true }), tags.extract(content, { lexical = true }) } do
      for _, match in ipairs(matches) do
        found = found + 1
        assert(doc:intersects(Range.new(1, match.range.start_col, 1, match.range.end_col), Document.INLINE_EXCLUSIONS))
      end
    end
    assert(found == 2, "expected a lexical link and tag in the fenced line")
  end)
end

return T
