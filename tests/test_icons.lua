local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["picker entry icons"] = new_set()

T["picker entry icons"]["missing user data wins over filetype"] = function()
  local icons = require "obsidian.icons"

  eq(
    icons.kinds.missing.icon,
    icons.get_icon {
      filename = "Missing.pdf",
      user_data = { attachment = true, missing = true },
    }
  )
end

T["picker entry icons"]["covers cache attachment filetypes"] = function()
  local icons = require "obsidian.icons"

  for _, ext in ipairs(require("obsidian.attachment").filetypes) do
    local icon = icons.get_icon { filename = "attachment." .. ext }
    eq("string", type(icon))
    assert(icon ~= "", "missing icon for " .. ext)
  end
end

return T
