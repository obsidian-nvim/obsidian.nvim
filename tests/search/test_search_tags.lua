local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T, child = h.child_vault()

local tmp_file = function(root)
  local filepath = vim.fs.joinpath(root, "test.md")
  local file = [==[
---
tags:
   - Book
   - Movie
---

#Book

- Book
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)
end

T["should return both frontmatter and inline tags"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_file(root)
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

T["should search specific tags"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_file(root)
  child.lua [[
local search = require"obsidian.search"
search.find_tags_async("Book", function(res)
   _G.res = res
end, {})
  ]]
  vim.uv.sleep(100)
  local res = child.lua_get [[res]]

  eq(#res, 2)
  eq(res[1].tag, "Book")
  eq(res[1].text, "- Book")
  eq(res[1].line, 3) -- 1-indexed

  eq(res[2].tag, "Book")
  eq(res[2].text, "#Book")
  eq(res[2].line, 7) -- 1-indexed
end


T["should ignore other frontmatter fields that look like tags"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "frontmatter_test.md")
  local file = [==[
---
tags:
  - real-tag
Other Field:
  - not-a-tag
---
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

  eq(#res, 1)
  eq(res[1].tag, "real-tag")
end
return T
