local search = require "obsidian.search"
local RefTypes = search.RefTypes
local Patterns = search.Patterns

-- describe("search.find_async", function()
--   it("should find files with search term in name", function()
--     local fixtures = vim.fs.joinpath(vim.uv.cwd(), "tests", "fixtures", "notes")
--     local match_counter = 0
--
--     search.find_async(fixtures, "foo", {}, function(match)
--       MiniTest.expect.equality(true, match:find "foo" ~= nil)
--       match_counter = match_counter + 1
--     end, function(exit_code)
--       MiniTest.expect.equality(0, exit_code)
--       MiniTest.expect.equality(2, match_counter)
--     end)
--   end)
-- end)

describe("search.search_async", function()
  it("should find files with search term in content", function()
    local fixtures = vim.fs.joinpath(vim.uv.cwd(), "tests", "fixtures", "notes")
    local match_counter = 0
    search.search_async(fixtures, "foo", {}, function(match)
      MiniTest.expect.equality("foo", match.submatches[1].match.text)
      match_counter = match_counter + 1
    end, function(exit_code)
      MiniTest.expect.equality(0, exit_code)
      MiniTest.expect.equality(8, match_counter)
    end)
  end)
end)

describe("search.find_refs()", function()
  it("should find positions of all refs", function()
    local s = "[[Foo]] [[foo|Bar]]"
    MiniTest.expect.equality({ { 1, 7, RefTypes.Wiki }, { 9, 19, RefTypes.WikiWithAlias } }, search.find_refs(s))
  end)

  it("should ignore refs within an inline code block", function()
    local s = "`[[Foo]]` [[foo|Bar]]"
    MiniTest.expect.equality({ { 11, 21, RefTypes.WikiWithAlias } }, search.find_refs(s))

    s = "[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) (triggered by typing `[[` for wiki links or "
      .. "just `[` for markdown links), powered by [`ripgrep`](https://github.com/BurntSushi/ripgrep)"
    MiniTest.expect.equality({ { 1, 47, RefTypes.Markdown }, { 134, 183, RefTypes.Markdown } }, search.find_refs(s))
  end)

  it("should find block IDs at the end of a line", function()
    MiniTest.expect.equality(
      { { 14, 25, RefTypes.BlockID } },
      search.find_refs("Hello World! ^hello-world", { include_block_ids = true })
    )
  end)
end)

describe("search.find_and_replace_refs()", function()
  it("should find and replace all refs", function()
    local s, indices = search.find_and_replace_refs "[[Foo]] [[foo|Bar]]"
    local expected_s = "Foo Bar"
    local expected_indices = { { 1, 3 }, { 5, 7 } }
    MiniTest.expect.equality(s, expected_s)
    MiniTest.expect.equality(#indices, #expected_indices)
    for i = 1, #indices do
      MiniTest.expect.equality(indices[i][1], expected_indices[i][1])
      MiniTest.expect.equality(indices[i][2], expected_indices[i][2])
    end
  end)
end)

describe("search.replace_refs()", function()
  it("should remove refs and links from a string", function()
    MiniTest.expect.equality(search.replace_refs "Hi there [[foo|Bar]]", "Hi there Bar")
    MiniTest.expect.equality(search.replace_refs "Hi there [[Bar]]", "Hi there Bar")
    MiniTest.expect.equality(search.replace_refs "Hi there [Bar](foo)", "Hi there Bar")
    MiniTest.expect.equality(search.replace_refs "Hi there [[foo|Bar]] [[Baz]]", "Hi there Bar Baz")
  end)
end)

describe("search.RefTypes", function()
  it("should have all keys matching values", function()
    for k, v in pairs(RefTypes) do
      assert(k == v)
    end
  end)
end)

describe("search.Patterns", function()
  it("should include a pattern for every RefType", function()
    for _, ref_type in pairs(RefTypes) do
      assert(type(Patterns[ref_type]) == "string")
    end
  end)
end)
