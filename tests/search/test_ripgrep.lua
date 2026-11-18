local M = require "obsidian.search.ripgrep"
local Path = require "obsidian.path"
local h = require "tests.helpers"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

-- TODO: standardize three ways of passing in options

T["find_cmd works"] = function()
  local out = vim.system(M.build_find_cmd(assert(vim.uv.cwd()), { sort_by = false })):wait()
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

T["read_lines_async returns complete logical lines"] = function()
  local dir = Path.temp { suffix = "-ripgrep-lines" }
  dir:mkdir { parents = true }
  local first = tostring(dir / "first.md")
  local second = tostring(dir / "second.canvas")
  vim.fn.writefile({ "alpha", "", "héllo" }, first)
  vim.fn.writefile({ '{"text":"canvas"}' }, second)

  local result, read_error
  M.read_lines_async({ first, second }, function(value, err)
    result, read_error = value, err
  end, { chunk_size = 1, max_jobs = 1 })
  h.wait(function()
    return result ~= nil or read_error ~= nil
  end, { desc = "ripgrep line transport" })

  eq(nil, read_error)
  eq({ "alpha", "", "héllo" }, result.lines[first])
  eq({ '{"text":"canvas"}' }, result.lines[second])
  vim.fn.delete(tostring(dir), "rf")
end

return T
