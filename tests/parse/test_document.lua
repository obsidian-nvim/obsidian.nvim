local Document = require "obsidian.parse.document"
local Pos = require "obsidian.pos"
local Range = require "obsidian.range"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local function kinds(doc)
  return vim.tbl_map(function(region)
    return region.kind
  end, doc.regions)
end

T["preserves source and recognizes frontmatter boundaries"] = function()
  local lines = { "\239\187\191---- \t", "tags: [one]  ", "---", "body", "---" }
  local doc = Document.parse(lines)
  lines[2] = "changed"

  eq(doc.lines, { "\239\187\191---- \t", "tags: [one]  ", "---", "body", "---" })
  eq(doc.frontmatter.range, Range.new(0, 0, 3, 0))
  eq(doc.frontmatter.opener_range, Range.new(0, 3, 0, 9))
  eq(doc.frontmatter.closer_range, Range.new(2, 0, 2, 3))
  eq(doc.frontmatter.body_range, Range.new(1, 0, 2, 0))
  eq(doc.frontmatter.termination, "delimiter")
end

T["protects an unfinished frontmatter and does not accept later openers"] = function()
  local unfinished = Document.parse { "---", "key: value" }
  eq(unfinished.frontmatter.range, Range.new(0, 0, 2, 0))
  eq(unfinished.frontmatter.termination, "eof")
  eq(Document.parse({ "", "---", "body" }).frontmatter, nil)
end

T["recognizes backtick and tilde fences and their exact closers"] = function()
  local doc = Document.parse {
    "````lua",
    "<!-- literal -->",
    "```",
    "`````  ",
    "text",
    "~~~lang",
    "x",
    "~~~ nope",
    "~~~~",
  }
  eq(kinds(doc), { "fenced_code", "fenced_code" })
  eq(doc.regions[1].range, Range.new(0, 0, 4, 0))
  eq(doc.regions[1].termination, "delimiter")
  eq(doc.regions[1].closer_range, Range.new(3, 0, 3, 5))
  eq(doc.regions[2].range, Range.new(5, 0, 9, 0))
end

T["does not turn indented fences or same-line backticks into fenced blocks"] = function()
  local doc = Document.parse { "    ```", "code", "```x```", "after" }
  eq(kinds(doc), { "indented_code", "code_span" })
  eq(doc.regions[1].range, Range.new(0, 0, 1, 0))
  eq(doc.regions[2].range, Range.new(2, 0, 2, 7))
end

T["bounds unclosed fences by quote and list containers"] = function()
  local quote = Document.parse { "> ```", "> code", "outside" }
  eq(quote.regions[1].range, Range.new(0, 0, 2, 0))
  eq(quote.regions[1].termination, "block_end")

  local list = Document.parse { "- ```", "  code", "  ```", "outside" }
  eq(list.regions[1].range, Range.new(0, 0, 3, 0))
  eq(list.regions[1].termination, "delimiter")

  local continued_list = Document.parse { "- item", "  ```", "  code", "outside" }
  eq(continued_list.regions[1].range, Range.new(1, 0, 3, 0))
  eq(continued_list.regions[1].termination, "block_end")

  local nested = Document.parse { "- outer", "    - inner", "        ~~~", "        code", "        ~~~" }
  eq(nested.regions[1].range, Range.new(2, 0, 5, 0))
end

T["recognizes indented code without interrupting paragraphs"] = function()
  local doc = Document.parse { "paragraph", "    continuation", "", "    code", "", "plain" }
  eq(kinds(doc), { "indented_code" })
  eq(doc.regions[1].range, Range.new(3, 0, 4, 0))

  local quoted = Document.parse { ">", ">     code", ">     more", "outside" }
  eq(quoted.regions[1].range, Range.new(1, 0, 3, 0))
end

T["pairs exact backtick runs across paragraph lines"] = function()
  local doc = Document.parse {
    "a `` one `",
    "two `` visible",
    "an unmatched ` opener",
    "",
    "next",
  }
  eq(kinds(doc), { "code_span" })
  eq(doc.regions[1].range, Range.new(0, 2, 1, 6))
  eq(doc.regions[1].termination, "delimiter")

  local followed_by_block = Document.parse { "`one", "two`", "~~~", "literal", "~~~" }
  eq(kinds(followed_by_block), { "code_span", "fenced_code" })
  eq(followed_by_block.regions[2].range, Range.new(2, 0, 5, 0))

  local quoted = Document.parse { "> before `one", "> two` after" }
  eq(quoted.regions[1].range, Range.new(0, 9, 1, 6))

  local escaped = Document.parse { "\\`` not code `` but `yes`" }
  eq(kinds(escaped), { "code_span" })
  eq(escaped.regions[1].range, Range.new(0, 20, 0, 25))
end

T["keeps comment syntax in code literal and code syntax in comments literal"] = function()
  local doc = Document.parse {
    "`<!-- not comment --> %% no %%` <!-- ` not code -->",
    "```",
    "%% not comment %%",
    "```",
    "%% `not code` <!-- no --> %%",
  }
  eq(kinds(doc), { "code_span", "html_comment", "fenced_code", "obsidian_comment" })
end

T["supports inline and multiline Obsidian comments without fake blocks"] = function()
  local doc = Document.parse {
    "before %% hidden",
    "```fake",
    "# heading",
    "%% after `code`",
  }
  eq(kinds(doc), { "obsidian_comment", "code_span" })
  eq(doc.regions[1].range, Range.new(0, 7, 3, 2))
  eq(doc.regions[2].range, Range.new(3, 9, 3, 15))
end

T["uses editing-safe recovery for unfinished comments"] = function()
  local html = Document.parse { "text <!-- open", "continued", "", "body" }
  eq(html.regions[1].range, Range.new(0, 5, 1, 9))
  eq(html.regions[1].termination, "incomplete")

  local obsidian = Document.parse { "text %% open", "", "body" }
  eq(obsidian.regions[1].range, Range.new(0, 5, 3, 0))
  eq(obsidian.regions[1].termination, "eof")
end

T["distinguishes block HTML extent from its precise comment"] = function()
  local doc = Document.parse { "  <!-- hidden", "end --> visible", "body" }
  eq(kinds(doc), { "html_block", "html_comment" })
  eq(doc.regions[1].range, Range.new(0, 0, 2, 0))
  eq(doc.regions[2].range, Range.new(0, 2, 1, 7))
  eq(doc.regions[2].closer_range, Range.new(1, 4, 1, 7))
  local context = doc:context_at(Pos.new(1, 5))
  eq(context.html_block, doc.regions[1])
  eq(context.comment, doc.regions[2])

  local short = Document.parse { "<!--->", "body" }
  eq(short.regions[1].range, Range.new(0, 0, 1, 0))
  eq(short.regions[2].range, Range.new(0, 0, 0, 6))
end

T["answers half-open point, overlap, and clipped-row queries"] = function()
  local doc = Document.parse { "before `code` after", "%% one", "two %% end" }
  local code = doc.regions[1]
  eq(doc:context_at(Pos.new(0, 6)).code_span, nil)
  eq(doc:context_at(Pos.new(0, 7)).code_span, code)
  eq(doc:context_at(Pos.new(0, 12)).code_span, code)
  eq(doc:context_at(Pos.new(0, 13)).code_span, nil)

  eq(doc:intersects(Range.new(0, 0, 0, 7), "code_span"), false)
  eq(doc:intersects(Range.new(0, 12, 0, 15), { code_span = true }), true)
  eq(doc:intersects(Range.new(0, 8, 0, 8)), false)
  eq(doc:ranges_on_row(1, "obsidian_comment"), { Range.new(1, 0, 1, 6) })
  eq(doc:ranges_on_row(2, { "obsidian_comment" }), { Range.new(2, 0, 2, 6) })
end

T["validates snapshot coordinates and handles empty snapshots"] = function()
  local empty = Document.parse {}
  eq(empty.regions, {})
  eq(
    pcall(function()
      empty:context_at(Pos.new(0, 0))
    end),
    false
  )

  local doc = Document.parse { "é text" }
  eq(
    pcall(function()
      doc:context_at(Pos.new(0, 8))
    end),
    false
  )
  eq(
    pcall(function()
      doc:intersects(Range.new(0, 0, 1, 0))
    end),
    true
  )
  eq(
    pcall(function()
      doc:intersects(Range.new(1, 0, 1, 1))
    end),
    false
  )
end

return T
