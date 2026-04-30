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
---

#Idea
]==],
    ["gamma.md"] = [==[
---
tags:
   - Movie
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

  local call = run_tags { "Book" }

  eq(call.prompt_title, "OR: #book")
  eq(#call.entries, 4)
  eq(entry_displays(call.entries), {
    "alpha [3] - Book",
    "alpha [7] #Book",
    "alpha [8] #Book/sub",
    "beta [3] - Book",
  })
end

T["hash-prefixed tag search returns only inline locations"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "#Book" }

  eq(call.prompt_title, "OR inline: #book")
  eq(#call.entries, 2)
  eq(call.entries[1].display, "alpha [7] #Book")
  eq(call.entries[1].lnum, 7)
  eq(call.entries[2].display, "alpha [8] #Book/sub")
  eq(call.entries[2].lnum, 8)
end

T["multiple tags default to OR note matches"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "Project", "Movie" }

  eq(call.prompt_title, "OR: #project, #movie")
  eq(#call.entries, 2)
  eq(entry_displays(call.entries), {
    "alpha [OR: project]",
    "gamma [OR: movie]",
  })
end

T["plus-prefixed tag enables AND note matches"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags { "+Book", "Project" }

  eq(call.prompt_title, "AND: #book, #project")
  eq(#call.entries, 1)
  eq(call.entries[1].display, "alpha [AND: book, project]")
end

T["no arguments keeps the tag list picker behavior"] = function()
  local root = child.lua_get [[tostring(Obsidian.dir)]]
  tmp_files(root)

  local call = run_tags {}

  eq(call.entries, { "book", "book/sub", "idea", "movie", "project" })
  eq(call.allow_multiple, true)
  eq(call.has_callback, true)
end

return T
