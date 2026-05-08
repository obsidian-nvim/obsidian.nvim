local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[T = require"obsidian.textobj"]],
}

---Set buffer to a single line and place cursor at given 0-indexed col.
local function set_line(line, col)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  child.api.nvim_win_set_cursor(0, { 1, col })
end

---@return string
local function get_line()
  return child.api.nvim_buf_get_lines(0, 0, -1, false)[1]
end

T["transform_link"] = new_set()

T["transform_link"]["wiki without alias keeps location"] = function()
  set_line("see [[Other Note]] today", 6)
  child.lua [[T.transform_link()]]
  eq("see Other Note today", get_line())
end

T["transform_link"]["wiki with alias keeps name"] = function()
  set_line("see [[Other Note|the other]] today", 6)
  child.lua [[T.transform_link()]]
  eq("see the other today", get_line())
end

T["transform_link"]["wiki strips anchor when no alias"] = function()
  set_line("see [[Other Note#Heading]] today", 6)
  child.lua [[T.transform_link()]]
  eq("see Other Note today", get_line())
end

T["transform_link"]["markdown URL becomes autolink"] = function()
  set_line("read [docs](https://example.com) now", 8)
  child.lua [[T.transform_link()]]
  eq("read <https://example.com> now", get_line())
end

T["transform_link"]["markdown internal link keeps name"] = function()
  set_line("see [the other](other.md) today", 8)
  child.lua [[T.transform_link()]]
  eq("see the other today", get_line())
end

T["transform_link"]["markdown internal empty name keeps location"] = function()
  set_line("see [](other.md) today", 6)
  child.lua [[T.transform_link()]]
  eq("see other.md today", get_line())
end

T["transform_link"]["attachment is removed without prompt when file missing"] = function()
  set_line("img ![alt](missing.png) here", 6)
  child.lua [[T.transform_link()]]
  eq("img  here", get_line())
end

T["transform_link"]["no link at cursor is a no-op"] = function()
  set_line("plain text only", 4)
  child.lua [[T.transform_link()]]
  eq("plain text only", get_line())
end

T["transform_link"]["picks outer link when nested"] = function()
  set_line("x [[a]] y", 3)
  child.lua [[T.transform_link()]]
  eq("x a y", get_line())
end

return T
