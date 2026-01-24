local parse = require("obsidian.slides.parse").parse

local eq = MiniTest.expect.equality

describe("present.parse_slides", function()
  it("should parse an empty file", function()
    local slides = parse { "" }

    eq({
      {
        title = "",
        body = {},
      },
    }, slides)
  end)

  it("should parse a file with one slide", function()
    eq(
      {
        {
          title = "# This is the first slide",
          body = { "This is the body" },
        },
      },
      parse {
        "# This is the first slide",
        "This is the body",
      }
    )
  end)

  it("should parse a file with one slide", function()
    local results = parse {
      "# This is the first slide",
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }

    -- Should only have one slide
    eq(1, #results)

    local slide = results[1]
    eq("# This is the first slide", slide.title)
    eq({
      "This is the body",
      "```lua",
      "print('hi')",
      "```",
    }, slide.body)
  end)

  it("should use stop comment to stop slides", function()
    local results = parse {
      "# This is the first slide",
      "This is the body",
      "---",
      "This is the middle line",
      "---",
      "This is the final line",
    }

    -- Should only have two slides (even though only one separator)
    eq(3, #results)

    local slide = results[1]
    eq("# This is the first slide", slide.title)
    eq("This is the body", slide.body[1])

    slide = results[2]
    eq("", slide.title)
    eq("This is the middle line", slide.body[1])

    slide = results[3]
    eq("", slide.title)
    eq("This is the final line", slide.body[1])
  end)

  it("should use ignore comments", function()
    local results = parse {
      "# This is the first slide",
      "%% This is a comment",
      "This is the body",
      "---",
      "This is the final line",
    }

    -- Should only have two slides (even though only one separator)
    eq(2, #results)

    local slide = results[1]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body" }, slide.body)

    slide = results[2]
    eq("# This is the first slide", slide.title)
    eq({ "This is the body", "This is the final line" }, slide.body)
  end)
end)
