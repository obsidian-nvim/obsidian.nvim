local CodeRunner = require "obsidian.code_runner"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local function with_buffer(lines, callback)
  local original_buf = vim.api.nvim_get_current_buf()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  callback(buf)
  vim.api.nvim_set_current_buf(original_buf)
  vim.api.nvim_buf_delete(buf, { force = true })
end

T["runs Lua and Vim fenced blocks"] = function()
  vim.g.obsidian_code_runner_test = nil
  with_buffer({
    "```lua",
    "vim.g.obsidian_code_runner_test = 'lua'",
    "```",
    "",
    "```vim",
    "let g:obsidian_code_runner_test = 'vim'",
    "```",
  }, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    CodeRunner.run()
    eq(vim.g.obsidian_code_runner_test, "lua")

    vim.api.nvim_win_set_cursor(0, { 6, 0 })
    CodeRunner.run()
    eq(vim.g.obsidian_code_runner_test, "vim")
  end)
  vim.g.obsidian_code_runner_test = nil
end

T["ignores unsupported blocks and registers the docs keymap"] = function()
  vim.g.obsidian_code_runner_test = nil
  with_buffer({ "```bash", "echo no", "```" }, function(buf)
    CodeRunner.setup(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    CodeRunner.run()

    eq(vim.g.obsidian_code_runner_test, nil)
    eq(
      vim.tbl_contains(
        vim.tbl_map(function(map)
          return map.lhs
        end, vim.api.nvim_buf_get_keymap(buf, "n")),
        "g=="
      ),
      true
    )
  end)
end

return T
