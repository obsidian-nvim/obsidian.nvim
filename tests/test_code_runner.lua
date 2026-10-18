local CodeRunner = require("obsidian").code_runner
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

T["passes parsed code and context to custom runners"] = function()
  local original_system = vim.system
  local received
  CodeRunner.add("test-runner", function(bufnr, code, context)
    received = { bufnr = bufnr, code = code, context = context }
    return { cmd = { "test-command", "--flag" } }
  end)

  vim.system = function(cmd, opts, callback)
    received.cmd = cmd
    received.stdin = opts.stdin
    callback { code = 0, stdout = "", stderr = "" }
  end

  with_buffer({ "```test-runner opts", "print('hello')", "```" }, function(buf)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    CodeRunner.run()

    eq(received.bufnr, buf)
    eq(received.code, "print('hello')")
    eq(received.stdin, received.code)
    eq(received.cmd, { "test-command", "--flag" })
    eq(received.context.filetype, "test-runner")
    eq(received.context.block.kind, "fenced_code")
    eq(received.context.range, received.context.block.range)
    eq(received.context.document.lines[1], "```test-runner opts")
  end)

  vim.system = original_system
end

T["strips Markdown container prefixes from code"] = function()
  vim.g.obsidian_code_runner_test = nil
  local original_system = vim.system
  local received
  CodeRunner.add("nested-test-runner", function(_, code)
    received = code
    return { cmd = { "test-command" } }
  end)
  vim.system = function(_, _, callback)
    callback { code = 0, stdout = "", stderr = "" }
  end

  with_buffer({
    "> ```lua",
    "> vim.g.obsidian_code_runner_test = 'quote'",
    "> ```",
    "",
    "- outer",
    "  - ~~~nested-test-runner",
    "    print('list')",
    "    ~~~",
    "",
    "1. item",
    "    > ~~~nested-test-runner",
    "    > print('continued list quote')",
    "    > ~~~",
  }, function()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    CodeRunner.run()
    eq(vim.g.obsidian_code_runner_test, "quote")

    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    CodeRunner.run()
    eq(received, "print('list')")

    vim.api.nvim_win_set_cursor(0, { 11, 0 })
    CodeRunner.run()
    eq(received, "print('continued list quote')")
  end)

  vim.system = original_system
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
