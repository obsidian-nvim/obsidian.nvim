local Range = require "obsidian.range"
local block_id = require "obsidian.parse.block_id"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["extract parses end-of-line block IDs"] = function()
  eq({
    {
      raw = "^block-id",
      range = Range.new(2, 21, 2, 30),
    },
  }, block_id.extract("Paragraph with block ^block-id", { row = 2 }))
end

T["extract ignores non-final block IDs"] = function()
  eq({}, block_id.extract "Paragraph ^block-id trailing")
end

T["extract ignores block IDs inside inline code"] = function()
  eq({}, block_id.extract "Paragraph `^block-id`")
end

return T
