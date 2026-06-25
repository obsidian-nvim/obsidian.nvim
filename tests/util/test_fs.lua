local M = require "obsidian.util"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["relpath"] = function()
  eq(M.relpath("/a", "/a/b"), "b")
  eq(M.relpath("/a/b/", "/a/d/e"), "../d/e")
  eq(M.relpath("/a/b/c", "/a"), "../..")
  eq(M.relpath("/a/b/c", "/a/d/e"), "../../d/e")
end

T["is_subpath"] = function()
  eq(true, M.is_subpath("/a/b", "/a"))
  eq(true, M.is_subpath("/a", "/a/"))
  eq(false, M.is_subpath("/ab", "/a"))
end

T["atomic_write"] = function()
  local path = vim.fn.tempname()
  M.atomic_write(path, "first")
  eq({ "first" }, vim.fn.readfile(path))
  M.atomic_write(path, "second")
  eq({ "second" }, vim.fn.readfile(path))
  eq(0, vim.fn.filereadable(path .. ".tmp"))
  vim.fn.delete(path)
end

T["find_unique"] = function()
  local taken = {
    foo = true,
    ["foo-1"] = true,
  }

  eq(
    "foo-2",
    M.find_unique("foo", function(value)
      return taken[value] == true
    end, function(_, attempt)
      return "foo-" .. attempt
    end)
  )

  eq(
    nil,
    M.find_unique("foo", function()
      return true
    end, function(_, attempt)
      return "foo-" .. attempt
    end, 2)
  )
end

return T
