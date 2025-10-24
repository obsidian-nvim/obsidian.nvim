local M = require "obsidian.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["tbl_unique"] = function()
  eq(#M.tbl_unique { "hi", "hey", "hi", "hi" }, 2)
end

T["match_case"] = new_set()

T["match_case"]["should match case of key to prefix"] = function()
  eq(M.match_case("Foo", "foo"), "Foo")
  eq(M.match_case("In-cont", "in-context learning"), "In-context learning")
end

T["unescape_single_backslash"] = new_set()

T["unescape_single_backslash"]["should correctly remove single backslash"] = function()
  -- [[123\|NOTE1]] should get [[123|NOTE1]] in markdown file
  -- in lua, it needs to be with double backslash '\\'
  eq(M.unescape_single_backslash "[[foo\\|bar]]", "[[foo|bar]]")
end

T["is_url"] = new_set()

T["is_url"]["should identify basic URLs"] = function()
  eq(true, M.is_url "https://example.com")
end

T["is_url"]["should identify semantic scholar API URLS"] = function()
  eq(true, M.is_url "https://api.semanticscholar.org/CorpusID:235829052")
end

T["is_url"]["should identify 'mailto' URLS"] = function()
  eq(true, M.is_url "mailto:mail@domain.com")
end

T["is_checkbox"] = new_set()

T["is_checkbox"]["should return true for valid checkbox list items"] = function()
  eq(true, M.is_checkbox "- [ ] Task 1")
  eq(true, M.is_checkbox "- [x] Task 1")
  eq(true, M.is_checkbox "+ [ ] Task 1")
  eq(true, M.is_checkbox "+ [x] Task 1")
  eq(true, M.is_checkbox "* [ ] Task 2")
  eq(true, M.is_checkbox "* [x] Task 2")
  eq(true, M.is_checkbox "1. [ ] Task 3")
  eq(true, M.is_checkbox "1. [x] Task 3")
  eq(true, M.is_checkbox "2. [ ] Task 3")
  eq(true, M.is_checkbox "10. [ ] Task 3")
  eq(true, M.is_checkbox "1) [ ] Task")
  eq(true, M.is_checkbox "10) [ ] Task")
end

T["is_checkbox"]["should return false for non-checkbox list items"] = function()
  eq(false, M.is_checkbox "- Task 1")
  eq(false, M.is_checkbox "-- Task 1")
  eq(true, M.is_checkbox "-- [ ] Task 1") -- TODO: bit shaky for now, but allows toggling in block quotes.
  eq(false, M.is_checkbox "* Task 2")
  eq(true, M.is_checkbox "++ [ ] Task 2")
  eq(false, M.is_checkbox "1. Task 3")
  eq(false, M.is_checkbox "1.1 Task 3")
  eq(false, M.is_checkbox "1.1 [ ] Task 3")
  eq(false, M.is_checkbox "1)1 Task 3")
  eq(false, M.is_checkbox "Random text")
end

T["is_checkbox"]["should handle leading spaces correctly"] = function()
  eq(true, M.is_checkbox "  - [ ] Task 1")
  eq(true, M.is_checkbox "    * [ ] Task 2")
  eq(true, M.is_checkbox "     5. [ ] Task 2")

  eq(false, M.is_checkbox "    - Task 1")
  eq(false, M.is_checkbox "    * Task 1")
  eq(false, M.is_checkbox "    1. Task 1")
end

T["is_whitespace"] = function()
  eq(true, M.is_whitespace "  ")
  eq(false, M.is_whitespace "a  ")
end

T["is_hex_color"] = new_set()

T["is_hex_color"]["recognizes valid hex colors"] = function()
  eq(M.is_hex_color "#abc", true)
  eq(M.is_hex_color "#abcd", true)
  eq(M.is_hex_color "#aabbcc", true)
  eq(M.is_hex_color "#aabbccdd", true)
end

T["is_hex_color"]["rejects invalid hex colors"] = function()
  eq(M.is_hex_color "#ab", false)
  eq(M.is_hex_color "#abcde", false)
  eq(M.is_hex_color "#aabbccfg", false)
  eq(M.is_hex_color "#aabbccdde", false)
end

T["is_hex_color"]["rejects invalid chars"] = function()
  eq(M.is_hex_color "#ggg", false)
  eq(M.is_hex_color "#12345z", false)
  eq(M.is_hex_color "#xyzxyz", false)
end

T["count_indent"] = new_set()

T["count_indent"]["should count each space as one indent"] = function()
  eq(2, M.count_indent "  ")
end

T["count_indent"]["should count each tab as one indent"] = function()
  eq(2, M.count_indent "		")
end

T["header_level"] = new_set()

T["header_level"]["should return 0 when the line is not a header"] = function()
  eq(0, M.header_level "Hello World")
  eq(0, M.header_level "#Hello World")
end

T["header_level"]["should return 1 for H1 headers"] = function()
  eq(1, M.header_level "# Hello World")
end

T["header_level"]["should return 2 for H2 headers"] = function()
  eq(2, M.header_level "## Hello World")
end

T["previous_day"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(M.previous_day(now), os.time { year = 2025, month = 4, day = 26 })
end

T["next_day"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(M.next_day(now), os.time { year = 2025, month = 4, day = 28 })
end

T["working_day_before"] = function()
  local now = os.time { year = 2025, month = 4, day = 27 }
  eq(M.working_day_before(now), os.time { year = 2025, month = 4, day = 25 })
end

T["working_day_after"] = function()
  local now = os.time { year = 2025, month = 4, day = 25 }
  eq(M.working_day_after(now), os.time { year = 2025, month = 4, day = 28 })
end

T["next_item"] = new_set()

T["next_item"]["should pull out next list item with enclosing quotes"] = function()
  eq('"foo"', M.next_item([=["foo", "bar"]=], { "," }))
end

T["next_item"]["should pull out the last list item with enclosing quotes"] = function()
  eq('"foo"', M.next_item([=["foo"]=], { "," }))
end

T["next_item"]["should pull out the last list item with enclosing quotes and stop char"] = function()
  eq('"foo"', M.next_item([=["foo",]=], { "," }))
end

T["next_item"]["should pull out next list item without enclosing quotes"] = function()
  eq("foo", M.next_item([=[foo, "bar"]=], { "," }))
end

T["next_item"]["should pull out next list item even when the item contains the stop char"] = function()
  eq('"foo, baz"', M.next_item([=["foo, baz", "bar"]=], { "," }))
end

T["next_item"]["should pull out the last list item without enclosing quotes"] = function()
  eq("foo", M.next_item([=[foo]=], { "," }))
end

T["next_item"]["should pull out the last list item without enclosing quotes and stop char"] = function()
  eq("foo", M.next_item([=[foo,]=], { "," }))
end

T["next_item"]["should pull nested array"] = function()
  eq("[foo, bar]", M.next_item("[foo, bar],", { "]" }, true))
end

T["next_item"]["should pull out the key in an array"] = function()
  local next_item, str = M.next_item("foo: bar", { ":" }, false)
  eq("foo", next_item)
  eq(" bar", str)
  next_item, str = M.next_item("bar: 1, baz: 'Baz'", { ":" }, false)
  eq("bar", next_item)
  eq(" 1, baz: 'Baz'", str)
end

T["parse"] = new_set()

T["parse"]["block"] = new_set()

T["parse"]["block"]["should parse basic block identifiers"] = function()
  local block = M.parse_block "Foo Bar ^hello-world"
  eq("^hello-world", block)
end

T["parse"]["header"] = new_set()

T["parse"]["header"]["should include spaces"] = function()
  eq({ header = "Hello World", level = 2, anchor = "#hello-world" }, M.parse_header "## Hello World")
  eq({ header = "Hello World", level = 1, anchor = "#hello-world" }, M.parse_header "# Hello World")
end

T["parse"]["header"]["should include extra spaces at the beginning"] = function()
  eq({ header = "Hello World", level = 2, anchor = "#hello-world" }, M.parse_header "##  Hello World")
end

T["parse"]["header"]["should strip white space at the end"] = function()
  eq({ header = "Hello World", level = 2, anchor = "#hello-world" }, M.parse_header "## Hello World ")
end

-- TODO: test for all link types
T["parse"]["link"] = new_set()

T["parse"]["link"]["should parse link"] = function()
  local location = M.parse_link "[[hi#^block]]"
  eq(location, "hi#^block")
end

T["parse"]["link"]["should strip if specified"] = function()
  local location = M.parse_link("[[hi#^block]]", { strip = true })
  eq(location, "hi")
end

T["parse"]["link"]["parse footnote link"] = function()
  local location, name, link_type = M.parse_link("[^1]", {})
  eq("1", location)
  eq("1", name)
  eq(require("obsidian.search").RefTypes.Footnote, link_type)
end

T["strip"] = new_set()

T["strip"]["block_links"] = new_set()

T["strip"]["block_links"]["should strip basic block links"] = function()
  local line, block = M.strip_block_links "Foo Bar#^hello-world"
  eq("Foo Bar", line)
  eq("#^hello-world", block)
end

T["strip"]["block_links"]["should strip block links from an otherwise empty input"] = function()
  local line, block = M.strip_block_links "#^hello-world"
  eq("", line)
  eq("#^hello-world", block)
end

T["strip"]["anchor_links"] = new_set()

T["strip"]["anchor_links"]["should strip basic anchor links"] = function()
  local line, anchor = M.strip_anchor_links "Foo Bar#hello-world"
  eq("Foo Bar", line)
  eq("#hello-world", anchor)
end

T["strip"]["anchor_links"]["should strip even a single letter anchor link (for completion)"] = function()
  local line, anchor = M.strip_anchor_links "Foo Bar#H"
  eq("Foo Bar", line)
  eq("#h", anchor)
end

T["strip"]["anchor_links"]["should strip non-standard anchor links"] = function()
  local line, anchor = M.strip_anchor_links "Foo Bar#Hello World"
  eq("Foo Bar", line)
  eq("#hello-world", anchor)
end

T["strip"]["anchor_links"]["should strip multiple anchor links"] = function()
  local line, anchor = M.strip_anchor_links "Foo Bar#hello-world#sub-header"
  eq("Foo Bar", line)
  eq("#hello-world#sub-header", anchor)
end

T["strip"]["anchor_links"]["should leave line alone when there are no anchor links"] = function()
  local line, anchor = M.strip_anchor_links "Foo Bar"
  eq("Foo Bar", line)
  eq(nil, anchor)
end

T["strip"]["comments"] = new_set()

T["strip"]["comments"]["should strip comments from a string"] = function()
  eq("foo: 1", M.strip_comments "foo: 1  # this is a comment")
end

T["strip"]["comments"]["should strip comments even when they start at the beginning of the string"] = function()
  eq("", M.strip_comments "# foo: 1")
end

T["strip"]["comments"]["should ignore '#' when enclosed in quotes"] = function()
  eq([["hashtags start with '#'"]], M.strip_comments [["hashtags start with '#'"]])
end

T["strip"]["comments"]["should ignore an escaped '#'"] = function()
  eq([[hashtags start with \# right?]], M.strip_comments [[hashtags start with \# right?]])
end

T["strip"]["left whitespace"] = new_set()

T["strip"]["left whitespace"]["should strip tabs and spaces from left end only"] = function()
  eq("foo ", M.lstrip_whitespace "	foo ")
end

T["strip"]["left whitespace"]["should respect the limit parameters"] = function()
  eq(" foo ", M.lstrip_whitespace("  foo ", 1))
end

T["uri"] = new_set()

T["uri"]["encode"] = new_set()
T["uri"]["encode"]["should correctly URL-encode a path"] = function()
  eq([[~%2FLibrary%2FFoo%20Bar.md]], M.urlencode [[~/Library/Foo Bar.md]])
end

T["uri"]["encode"]["should keep path separated when asks"] = function()
  eq([[~/Library/Foo%20Bar.md]], M.urlencode([[~/Library/Foo Bar.md]], { keep_path_sep = true }))
end

T["header_to_anchor"] = new_set()

T["header_to_anchor"]["should strip leading '#' and put everything in lowercase"] = function()
  eq("#hello-world", M.header_to_anchor "## Hello World")
end

T["header_to_anchor"]["should remove punctuation"] = function()
  eq("#hello-world", M.header_to_anchor "# Hello, World!")
end

T["header_to_anchor"]["should keep numbers"] = function()
  eq("#hello-world-123", M.header_to_anchor "# Hello, World! 123")
end

T["header_to_anchor"]["should keep underscores"] = function()
  eq("#hello_world", M.header_to_anchor "# Hello_World")
end

T["header_to_anchor"]["should have a '-' for every space"] = function()
  eq("#hello--world", M.header_to_anchor "# Hello  World!")
end

return T
