local ts = require "obsidian.ts"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["to_virt_lines"] = function()
  local lines = {
    "## heading",
    "",
    "**inline** and `code`",
  }

  eq(ts.to_virt_lines(lines), {
    { { "## heading", "@markup.heading.2.markdown" } },
    {},
    {
      { "inline", "@markup.strong.markdown_inline" },
      { " and " },
      { "code", "@markup.raw.markdown_inline" },
    },
  })
end

T["to_virt_lines stacks overlapping captures"] = function()
  eq(ts.to_virt_lines { "***both***" }, {
    {
      {
        "both",
        { "@markup.italic.markdown_inline", "@markup.strong.markdown_inline" },
      },
    },
  })
end

return T
