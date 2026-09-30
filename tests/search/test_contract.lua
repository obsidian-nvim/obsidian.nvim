local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local Ripgrep = require "obsidian.search.ripgrep"
local search = require "obsidian.search"

local T = h.temp_vault

T["async searches return cancellable handles"] = function()
  vim.fn.writefile({}, tostring(Obsidian.dir / "Note.md"))
  local original_has_ripgrep = Ripgrep._has_ripgrep
  Ripgrep._has_ripgrep = function()
    return false
  end

  local called = false
  local handle = search.find_notes_async("", function()
    called = true
  end)
  eq("function", type(handle.cancel))
  eq("function", type(handle.kill))
  handle:cancel()

  vim.wait(50)
  Ripgrep._has_ripgrep = original_has_ripgrep
  eq(false, called)
end

T["synchronous searches return backend errors separately from results"] = function()
  local original = search.find_notes_async
  search.find_notes_async = function(_, callback)
    callback({}, "backend failed")
    return require("obsidian.search.handle").noop()
  end

  local notes, err = search.find_notes "query"
  search.find_notes_async = original

  eq({}, notes)
  eq("backend failed", err)
end

return T
