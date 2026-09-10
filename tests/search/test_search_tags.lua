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
  local res = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      search.find_tags_async("", function(res)
        done(res)
      end, {})
    ]],
    { desc = "tags search" }
  )

  eq(#res, 3)
  eq(res[1].tag, "Book")
  eq(res[1].text, "   - Book")
  eq(res[1].line, 3) -- 1-indexed

  eq(res[2].tag, "Movie")
  eq(res[2].text, "   - Movie")
  eq(res[2].line, 4) -- 1-indexed

  eq(res[3].tag, "Book")
  eq(res[3].text, "#Book")
  eq(res[3].line, 7) -- 1-indexed
end

T["should search specific tags"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_file(root)
  local res = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      search.find_tags_async("Book", function(res)
        done(res)
      end, {})
    ]],
    { desc = "tags search" }
  )

  eq(#res, 2)
  eq(res[1].tag, "Book")
  eq(res[1].text, "   - Book")
  eq(res[1].line, 3) -- 1-indexed

  eq(res[2].tag, "Book")
  eq(res[2].text, "#Book")
  eq(res[2].line, 7) -- 1-indexed
end

T["should not error on frontmatter tags without an end boundary"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "test.md")
  local file = [==[
---
tags:
   - Book
]==]
  vim.fn.writefile(vim.split(file, "\n"), filepath)

  local res = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      search.find_tags_async("Book", function(res)
        done(res)
      end, {})
    ]],
    { desc = "tags search" }
  )

  eq(#res, 0)
  eq(child.lua_get [[vim.v.errmsg]], "")
end

T["should find frontmatter tags in files with DOS line endings"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
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
  -- Write the file with CRLF line endings (fileformat=dos).
  file = file:gsub("\n", "\r\n")
  vim.fn.writefile(vim.split(file, "\n", { plain = true }), filepath)

  local res = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      search.find_tags_async("", function(res)
        done(res)
      end, {})
    ]],
    { desc = "tags search" }
  )

  eq(#res, 3)
  eq(res[1].tag, "Book")
  eq(res[1].text, "   - Book")
  eq(res[1].line, 3)

  eq(res[2].tag, "Movie")
  eq(res[2].text, "   - Movie")
  eq(res[2].line, 4)

  eq(res[3].tag, "Book")
  eq(res[3].text, "#Book")
  eq(res[3].line, 7)
end

T["should keep visible tags beside comments and exclude opaque tags"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local filepath = vim.fs.joinpath(root, "excluded.md")
  vim.fn.writefile({
    "```",
    "#fenced",
    "```",
    "#before <!-- #hidden --> #after",
    "%% #commented %%",
    "`#coded`",
  }, filepath)

  local res = h.child_await(
    child,
    [[
      require("obsidian.search").find_tags_async("", function(res)
        done(res)
      end, {})
    ]],
    { desc = "filtered tags search" }
  )

  eq(
    { "before", "after" },
    vim.tbl_map(function(item)
      return item.tag
    end, res)
  )
  eq(1, res[1].tag_start)
  eq(26, res[2].tag_start)
end

T["filters individual tags and preserves source columns"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  h.write("  #Book #Movie", vim.fs.joinpath(root, "test.md"))

  local res = h.child_await(
    child,
    [[
      require("obsidian.search").find_tags_async("book", function(res)
        done(res)
      end, {})
    ]],
    { desc = "filtered tags search" }
  )

  eq(1, #res)
  eq("Book", res[1].tag)
  eq("  #Book #Movie", res[1].text)
  eq(3, res[1].tag_start)
  eq(7, res[1].tag_end)
  eq(2, res[1].range.start_col)
  eq(7, res[1].range.end_col)
end

T["finds scalar, flow-list, and block-list frontmatter tags with ranges"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["a.md"] = "---\ntags: Scalar\n---",
    ["b.md"] = "---\ntags: [Flow, 'Quoted']\n---",
    ["c.md"] = "---\ntags:\n  - Block\n---",
  })

  local res = h.child_await(
    child,
    [[
      require("obsidian.search").find_tags_async("", function(res)
        done(res)
      end, {})
    ]],
    { desc = "frontmatter tag forms" }
  )

  eq({ "Scalar", "Flow", "Quoted", "Block" }, vim.tbl_map(function(item)
    return item.tag
  end, res))
  eq({ 6, 7, 14, 4 }, vim.tbl_map(function(item)
    return item.range.start_col
  end, res))
  eq({ 12, 11, 20, 9 }, vim.tbl_map(function(item)
    return item.range.end_col
  end, res))
end

T["uses the same fenced-code exclusions as the cache"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  local path = vim.fs.joinpath(root, "test.md")
  h.write("```lua\n#Backtick\n```\n~~~lua\n#Tilde\n~~~\n#Visible", path)

  local result = h.child_await(
    child,
    ([=[
      local search = require "obsidian.search"
      search.find_tags_async("", function(res)
        local row = require("obsidian.cache.note").build(%q, tostring(Obsidian.dir))
        done({ locations = res, cached = row.tags })
      end, {})
    ]=]):format(path),
    { desc = "code-fence tag search" }
  )

  eq(1, #result.locations)
  eq("Visible", result.locations[1].tag)
  eq({ "visible" }, result.cached)
end

T["invokes its callback exactly once when search fails"] = function()
  local count = h.child_await(
    child,
    [[
      local search = require "obsidian.search"
      search.search_async = function(_, _, _, _, on_exit)
        on_exit(2)
      end
      local count = 0
      search.find_tags_async("tag", function()
        count = count + 1
        vim.defer_fn(function()
          done(count)
        end, 20)
      end, {})
    ]],
    { desc = "failed tags search callback" }
  )

  eq(1, count)
end

T["search and cache reuse YAML scalar occurrences"] = function()
  local path = vim.fs.joinpath(child.lua_get [[tostring(Obsidian.dir)]], "test.md")
  h.write("---\naliases: [NotATag]\ntags:\n\n- '#É'\n- 'it''s'\n- 2026\n---", path)
  local result = h.child_await(
    child,
    ([=[
      require("obsidian.search").find_tags_async("", function(res)
        local row = require("obsidian.cache.note").build(%q, tostring(Obsidian.dir))
        done({ locations = res, cached = row.tags })
      end, {})
    ]=]):format(path),
    { desc = "ranged YAML tags" }
  )
  eq({ "É", "it's", "2026" }, vim.tbl_map(function(item)
    return item.tag
  end, result.locations))
  eq({ "é", "it's", "2026" }, result.cached)
  eq({ 5, 6, 7 }, vim.tbl_map(function(item)
    return item.line
  end, result.locations))
  eq(4, result.locations[1].range.start_col)
  eq(6, result.locations[1].range.end_col)
  eq(3, result.locations[2].range.start_col)
  eq(8, result.locations[2].range.end_col)
end

return T
