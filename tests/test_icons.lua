local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["picker entry icons"] = new_set()

T["picker entry icons"]["missing user data wins over filetype"] = function()
  local icons = require "obsidian.icons"

  eq(
    icons.kinds.missing_attachment,
    icons.get_icon {
      filename = "Missing.pdf",
      user_data = { attachment = true, missing = true },
    }
  )

  eq(
    icons.kinds.missing,
    icons.get_icon {
      filename = "Missing.md",
      user_data = { missing = true },
    }
  )
end

T["picker entry icons"]["covers obsidian note filetypes"] = function()
  local icons = require "obsidian.icons"

  for _, ext in ipairs { "md", "markdown", "qmd", "canvas" } do
    local icon = icons.get_icon { filename = "note." .. ext }
    eq("string", type(icon))
    assert(icon ~= "", "missing icon for " .. ext)
  end

  eq(icons.kinds.base, icons.get_icon { filename = "note.base" })
end

T["picker entry icons"]["covers cache attachment filetypes"] = function()
  local icons = require "obsidian.icons"

  for _, ext in ipairs(require("obsidian.attachment").filetypes) do
    local icon = icons.get_icon { filename = "attachment." .. ext }
    eq("string", type(icon))
    assert(icon ~= "", "missing icon for " .. ext)
  end
end

T["picker entry icons"]["provides bookmark icons"] = function()
  local icons = require "obsidian.icons"

  eq(icons.kinds.bookmark, icons.get_bookmark_icon { type = "group" })
  eq(icons.kinds.url, icons.get_bookmark_icon { type = "url" })
  eq(icons.kinds.search, icons.get_bookmark_icon { type = "search" })
end

return T
