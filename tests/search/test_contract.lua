local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local Ripgrep = require "obsidian.search.ripgrep"
local search = require "obsidian.search"

local T = h.temp_vault

T["async searches return cancellable handles"] = function()
  local Handle = require "obsidian.search.handle"
  local original_find_async = Ripgrep.find_async
  local finish_backend
  local backend_finished = false
  Ripgrep.find_async = function(_, _, _, _, on_exit)
    finish_backend = function()
      on_exit(0)
      vim.schedule(function()
        backend_finished = true
      end)
    end
    return Handle.noop()
  end

  local called = false
  local handle = search.find_notes_async("", function()
    called = true
  end)
  eq("function", type(handle.cancel))
  eq("function", type(handle.kill))
  handle:cancel()
  finish_backend()

  h.wait(function()
    return backend_finished
  end, { desc = "cancelled search backend completion" })
  Ripgrep.find_async = original_find_async
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
