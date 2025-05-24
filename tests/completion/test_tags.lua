local completion = require "obsidian.completion.tags"

describe("find_tags_start()", function()
  it("should find tags within line", function()
    MiniTest.expect.equality("tag", completion.find_tags_start "Foo bar #tag")
  end)

  it("should find tags at the beginning of a line", function()
    MiniTest.expect.equality("tag", completion.find_tags_start "#tag")
  end)

  it("should ignore anchor links", function()
    MiniTest.expect.equality(nil, completion.find_tags_start "[[#header")
    MiniTest.expect.equality(nil, completion.find_tags_start "[[Bar#header")
  end)
end)
