local M = require "obsidian.search.ripgrep"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

-- TODO: standardize three ways of passing in options

T["find_cmd works"] = function()
  local out = vim.system(M.build_find_cmd()):wait()
  eq(out.code, 0)
end

T["search_cmd works"] = function()
  local out = vim.system(M.build_search_cmd(assert(vim.uv.cwd()), "obsidian", {})):wait()
  eq(out.code, 0)
end

T["grep_cmd works"] = function()
  local cmds = M.build_grep_cmd()
  table.insert(cmds, "foo")
  local out = vim.system(cmds):wait()
  print(out.stderr)
  eq(out.code, 0)
end

return T
