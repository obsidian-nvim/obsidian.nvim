local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T, child = h.child_vault()

local tmp_files = function(root)
  local files = {
    ["alpha.md"] = [==[
---
tags:
   - Book
   - Project
---

#Book
#Book/sub
]==],
    ["beta.md"] = [==[
---
tags:
   - Book
   - Archive
---

#Idea
]==],
    ["gamma.md"] = [==[
---
tags:
   - Movie
---
]==],
    ["delta.md"] = [==[
---
tags:
   - Book
---
]==],
  }

  for name, content in pairs(files) do
    vim.fn.writefile(vim.split(content, "\n"), vim.fs.joinpath(root, name))
  end
end

local install_picker_mock = function()
  child.lua [[
_G.picker_calls = {}
Obsidian.picker.pick = function(entries, opts)
  local clean_entries = {}

  for i, entry in ipairs(entries) do
    if type(entry) == "table" then
      clean_entries[i] = {
        display = entry.display,
        filename = entry.filename,
        lnum = entry.lnum,
        col = entry.col,
        value = entry.value and {
          path = entry.value.path and tostring(entry.value.path) or nil,
          line = entry.value.line,
          col = entry.value.col,
        } or nil,
      }
    else
      clean_entries[i] = entry
    end
  end

  _G.picker_calls[#_G.picker_calls + 1] = {
    entries = clean_entries,
    prompt_title = opts and opts.prompt_title or nil,
    allow_multiple = opts and opts.allow_multiple or nil,
    has_callback = opts and type(opts.callback) == "function" or false,
  }
  _G.last_picker_callback = opts and opts.callback or nil
end
  ]]
end

---@param args string[]
local run_tags = function(args)
  install_picker_mock()
  child.lua("require('obsidian.commands.tags')({ fargs = " .. vim.inspect(args) .. " })")
  child.lua [[
vim.wait(1000, function()
  return #_G.picker_calls > 0
end)
  ]]
  return child.lua_get [=[_G.picker_calls[#_G.picker_calls]]=]
end

local entry_displays = function(entries)
  local displays = vim.tbl_map(function(entry)
    return entry.display
  end, entries)
  table.sort(displays)
  return displays
end

T["single tag search returns matching locations"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "tag:#Book" }

  eq(call.prompt_title, "Tags: tag:#book")
  eq(#call.entries, 5)
  eq(entry_displays(call.entries), {
    "alpha [3] - Book",
    "alpha [7] #Book",
    "alpha [8] #Book/sub",
    "beta [3] - Book",
    "delta [3] - Book",
  })
end

T["space-separated terms default to AND"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "Book", "Project" }

  eq(call.prompt_title, "Tags: tag:#book tag:#project")
  eq(#call.entries, 4)
  eq(entry_displays(call.entries), {
    "alpha [3] - Book",
    "alpha [4] - Project",
    "alpha [7] #Book",
    "alpha [8] #Book/sub",
  })
end

T["OR terms return matching tag locations"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "tag:#Project", "OR", "tag:#Movie" }

  eq(call.prompt_title, "Tags: tag:#project OR tag:#movie")
  eq(#call.entries, 2)
  eq(entry_displays(call.entries), {
    "alpha [4] - Project",
    "gamma [3] - Movie",
  })
end

T["negative tag terms exclude matching notes"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "Book", "-Archive" }

  eq(call.prompt_title, "Tags: tag:#book -tag:#archive")
  eq(#call.entries, 4)
  eq(entry_displays(call.entries), {
    "alpha [3] - Book",
    "alpha [7] #Book",
    "alpha [8] #Book/sub",
    "delta [3] - Book",
  })
end

T["no arguments keeps the tag list picker behavior"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags {}

  eq(call.entries, { "archive", "book", "book/sub", "idea", "movie", "project" })
  eq(call.allow_multiple, true)
  eq(call.has_callback, true)
end

T["tag picker selections build an AND query"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  install_picker_mock()
  child.lua "require('obsidian.commands.tags')({ fargs = {} })"
  child.lua [[
vim.wait(1000, function()
  return #_G.picker_calls > 0
end)
assert(type(_G.last_picker_callback) == "function")
_G.last_picker_callback({ user_data = "book" }, { user_data = "project" })
vim.wait(1000, function()
  return #_G.picker_calls > 1
end)
  ]]

  local call = child.lua_get [=[_G.picker_calls[#_G.picker_calls]]=]
  eq(call.prompt_title, "Tags: tag:#book tag:#project")
  eq(entry_displays(call.entries), {
    "alpha [3] - Book",
    "alpha [4] - Project",
    "alpha [7] #Book",
    "alpha [8] #Book/sub",
  })
end

return T
