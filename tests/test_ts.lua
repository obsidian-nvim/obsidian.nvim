local ts = require "obsidian.ts"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["collect_ts_highlight_lines"] = function()
  local src = [[
## heading

**inline**
   ]]
  local parser = vim.treesitter.get_string_parser(src, "markdown")
  local lines = ts.collect_ts_highlight_lines(parser, src)
  eq(lines, {
    [1] = { { "## heading", "@markup.heading.2.markdown" } },
    [2] = {},
    [3] = { { "inline", "@markup.strong.markdown_inline" } },
  })
end

return T
