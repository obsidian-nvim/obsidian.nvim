local parse = require("obsidian.slides.parse").parse

local eq, new_set = MiniTest.expect.equality, MiniTest.new_set

local T = new_set()

T["should parse an empty file"] = function()
  local slides = parse { "" }

  eq({
    {
      title = "",
      body = {},
    },
  }, slides)
end

T["should parse a file with one slide"] = function()
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
end

T["should parse a file with one slide"] = function()
  local slides = parse {
    "# This is the first slide",
    "This is the body",
    "```lua",
    "print('hi')",
    "```",
  }

  -- Should only have one slide
  eq(1, #slides)

  local slide = slides[1]
  eq("# This is the first slide", slide.title)
  eq({
    "This is the body",
    "```lua",
    "print('hi')",
    "```",
  }, slide.body)
end

T["should use stop comment to stop slides"] = function()
  local slides = parse {
    "# This is the first slide",
    "This is the body",
    "---",
    "This is the middle line",
    "---",
    "This is the final line",
  }

  -- Should only have two slides (even though only one separator)
  eq(3, #slides)

  local slide = slides[1]
  eq("# This is the first slide", slide.title)
  eq("This is the body", slide.body[1])

  slide = slides[2]
  eq("", slide.title)
  eq("This is the middle line", slide.body[1])

  slide = slides[3]
  eq("", slide.title)
  eq("This is the final line", slide.body[1])
end

T["should use ignore comments"] = function()
  local slides = parse {
    "# This is the first slide",
    "%%This is a comment%%",
    "This is the body",
    "---",
    "This is the final line",
  }

  eq(2, #slides)

  local slide = slides[1]
  eq("# This is the first slide", slide.title)
  eq({ "This is the body" }, slide.body)

  slide = slides[2]
  eq("", slide.title)
  eq({ "This is the final line" }, slide.body)
end

return T
