local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find_tags"], child = h.child_vault()

T["find_tags"]["should not return false postives"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "test.md")
  local file = [==[
---
tags:
   - Book
   - Movie
---

#Book
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)
  child.lua [[
local search = require"obsidian.search"
search.find_tags_async("", function(res)
   _G.res = res
end, {})
  ]]
  vim.uv.sleep(100)
  local res = child.lua_get [[res]]

  eq(#res, 3)
  eq(res[1].tag, "Book")
  eq(res[1].text, "- Book")
  eq(res[1].line, 3) -- 1-indexed

  eq(res[2].tag, "Movie")
  eq(res[2].text, "- Movie")
  eq(res[2].line, 4) -- 1-indexed

  eq(res[3].tag, "Book")
  eq(res[3].text, "#Book")
  eq(res[3].line, 7) -- 1-indexed
end

return T
