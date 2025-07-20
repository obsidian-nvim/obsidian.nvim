local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local T = new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "scripts/minimal_init.lua" }
      child.lua [[M = require"obsidian.api"]]
    end,
    post_once = child.stop,
  },
}

-- FIXME: somehow treesitter awareness makes these unusable
-- T["toggle_checkbox"] = new_set()
--
-- T["toggle_checkbox"]["should toggle between default states with - lists"] = function()
--   child.api.nvim_buf_set_lines(0, 0, -1, false, { "- [ ] dummy" })
--   eq("- [x] dummy", child.api.nvim_get_current_line())
--   child.lua [[M.toggle_checkbox()]]
--   eq("- [ ] dummy", child.api.nvim_get_current_line())
-- end
--
-- T["toggle_checkbox"]["should toggle between default states with * lists"] = function()
--   child.api.nvim_buf_set_lines(0, 0, -1, false, { "* [ ] dummy" })
--   child.lua [[M.toggle_checkbox()]]
--   eq("* [x] dummy", child.api.nvim_get_current_line())
--   child.lua [[M.toggle_checkbox()]]
--   eq("* [ ] dummy", child.api.nvim_get_current_line())
-- end
--
-- T["toggle_checkbox"]["should toggle between default states with numbered lists with ."] = function()
--   child.api.nvim_buf_set_lines(0, 0, -1, false, { "1. [ ] dummy" })
--   child.lua [[M.toggle_checkbox()]]
--   eq("1. [x] dummy", child.api.nvim_get_current_line())
--   child.lua [[M.toggle_checkbox()]]
--   eq("1. [ ] dummy", child.api.nvim_get_current_line())
-- end
--
-- T["toggle_checkbox"]["should toggle between default states with numbered lists with )"] = function()
--   child.api.nvim_buf_set_lines(0, 0, -1, false, { "1) [ ] dummy" })
--   child.lua [[M.toggle_checkbox()]]
--   eq("1) [x] dummy", child.api.nvim_get_current_line())
--   child.lua [[M.toggle_checkbox()]]
--   eq("1) [ ] dummy", child.api.nvim_get_current_line())
-- end
--
-- T["toggle_checkbox"]["should use custom states if provided"] = function()
--   local custom_states = { " ", "!", "x" }
--   local toggle_expr = string.format([[M.toggle_checkbox(%s)]], vim.inspect(custom_states))
--   child.api.nvim_buf_set_lines(0, 0, -1, false, { "- [ ] dummy" })
--   child.lua(toggle_expr)
--   eq("- [!] dummy", child.api.nvim_get_current_line())
--   child.lua(toggle_expr)
--   eq("- [x] dummy", child.api.nvim_get_current_line())
--   child.lua(toggle_expr)
--   eq("- [ ] dummy", child.api.nvim_get_current_line())
--   child.lua(toggle_expr)
--   eq("- [!] dummy", child.api.nvim_get_current_line())
-- end

T["cursor_link"] = function()
  --                                               0    5    10   15   20   25   30   35   40    45  50   55
  --                                               |    |    |    |    |    |    |    |    |    |    |    |
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "The [other](link/file.md) plus [[another/file.md|yet]] there" })

  local link1 = "[other](link/file.md)"
  local link2 = "[[another/file.md|yet]]"

  local tests = {
    { cur_col = 4, link = link1, t = "Markdown" },
    { cur_col = 6, link = link1, t = "Markdown" },
    { cur_col = 24, link = link1, t = "Markdown" },
    { cur_col = 31, link = link2, t = "WikiWithAlias" },
    { cur_col = 39, link = link2, t = "WikiWithAlias" },
    { cur_col = 53, link = link2, t = "WikiWithAlias" },
  }
  for _, test in ipairs(tests) do
    child.api.nvim_win_set_cursor(0, { 1, test.cur_col })
    local link, t = unpack(child.lua_get [[{ M.cursor_link() }]])
    eq(test.link, link)
    eq(test.t, t)
  end
end

T["cursor_tag"] = function()
  --                                               0    5    10   15   20   25
  --                                               |    |    |    |    |    |
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "- [ ] Do the dishes #TODO " })

  local tests = {
    { cur_col = 0, res = vim.NIL },
    { cur_col = 19, res = vim.NIL },
    { cur_col = 20, res = "TODO" },
    { cur_col = 24, res = "TODO" },
    { cur_col = 25, res = vim.NIL },
  }

  for _, test in ipairs(tests) do
    child.api.nvim_win_set_cursor(0, { 1, test.cur_col })
    local tag = child.lua [[return M.cursor_tag()]]
    eq(test.res, tag)
  end
end

T["cursor_heading"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "# Hello", "world" })
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  eq("Hello", child.lua([[return M.cursor_heading()]]).header)
  eq("#hello", child.lua([[return M.cursor_heading()]]).anchor)
  eq(1, child.lua([[return M.cursor_heading()]]).level)
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  eq(vim.NIL, child.lua [[return M.cursor_heading()]])
end

return T
