local h = dofile "tests/helpers.lua"
local T, child = h.child_vault {
  pre_case = [[M = require "obsidian.actions"]],
}
local eq = MiniTest.expect.equality

local function unlink(line, col)
  child.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  child.api.nvim_win_set_cursor(0, { 1, col })
  child.lua [[M.unlink()]]
  return child.api.nvim_get_current_line()
end

T["unlink preserves display text and falls back to the target stem"] = function()
  local path = tostring(child.Obsidian.dir / "current-note.md")
  child.fn.writefile({}, path)
  child.cmd("edit " .. vim.fn.fnameescape(path))

  local cases = {
    {
      line = "See [[folder/note.md|Display text]] now",
      col = 6,
      expected = "See Display text now",
    },
    {
      line = "See [[folder/my%20note.md#Heading]] now",
      col = 6,
      expected = "See my note now",
    },
    {
      line = "See [Display text](folder/note.md) now",
      col = 6,
      expected = "See Display text now",
    },
    {
      line = "See [](folder/note.md) now",
      col = 6,
      expected = "See note now",
    },
    {
      line = "See ![[assets/image.png]] now",
      col = 4,
      expected = "See image now",
    },
    {
      line = "See [[#Heading]] now",
      col = 6,
      expected = "See current-note now",
    },
    {
      line = "See [[folder/note.md|显示文字]] now",
      col = 6,
      expected = "See 显示文字 now",
    },
  }

  for _, case in ipairs(cases) do
    eq(case.expected, unlink(case.line, case.col))
  end
end

T["unlink only changes a link under the cursor"] = function()
  eq("[[one]] and two", unlink("[[one]] and [[two]]", 14))
  eq("plain text", unlink("plain text", 2))
  eq("claim[^note]", unlink("claim[^note]", 7))
end

return T
