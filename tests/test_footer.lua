local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["refreshes backlinks only for changes in other files"] = function()
  child.lua [[
    local path = vim.fs.joinpath(tostring(Obsidian.dir), "current.md")
    vim.fn.writefile({ "# Current" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))

    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end

    local Note = require "obsidian.note"
    local original_status = Note.status
    local calls = {}
    Note.status = function(_, update_backlinks, callback)
      calls[#calls + 1] = update_backlinks
      callback({ words = 1, chars = 2, properties = 0, backlinks = update_backlinks and 3 or nil })
    end

    require("obsidian.footer").start(0)
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })

    local watchfiles = require "obsidian.lsp.watchfiles"
    watchfiles.handle { {
      path = path,
      type = vim.lsp.protocol.FileChangeType.Changed,
    } }
    _G.calls_after_current_file = #calls

    watchfiles.handle { {
      path = vim.fs.joinpath(tostring(Obsidian.dir), "other.md"),
      type = vim.lsp.protocol.FileChangeType.Changed,
    } }

    _G.initial_update_backlinks = calls[1]
    _G.text_update_backlinks = calls[2]
    _G.external_update_backlinks = calls[3]
    _G.footer_update_interval = vim.g.obsidian_footer_update_interval
    Note.status = original_status
    vim.schedule = original_schedule
  ]]

  eq(true, child.lua_get "initial_update_backlinks")
  eq(false, child.lua_get "text_update_backlinks")
  eq(2, child.lua_get "calls_after_current_file")
  eq(true, child.lua_get "external_update_backlinks")
  eq(vim.NIL, child.lua_get "footer_update_interval")
end

T["does not compute backlinks when no display format uses them"] = function()
  child.lua [[
    local path = vim.fs.joinpath(tostring(Obsidian.dir), "current.md")
    vim.fn.writefile({ "# Current" }, path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    Obsidian.opts.footer.format = "{{words}} words"
    Obsidian.opts.statusline.enabled = false

    local original_schedule = vim.schedule
    vim.schedule = function(fn)
      fn()
    end

    local Note = require "obsidian.note"
    local original_status = Note.status
    local calls = {}
    Note.status = function(_, update_backlinks, callback)
      calls[#calls + 1] = update_backlinks
      callback { words = 1, chars = 2, properties = 0 }
    end

    require("obsidian.footer").start(0)
    require("obsidian.lsp.watchfiles").handle { {
      path = vim.fs.joinpath(tostring(Obsidian.dir), "other.md"),
      type = vim.lsp.protocol.FileChangeType.Changed,
    } }

    _G.initial_update_backlinks = calls[1]
    _G.call_count = #calls
    Note.status = original_status
    vim.schedule = original_schedule
  ]]

  eq(false, child.lua_get "initial_update_backlinks")
  eq(1, child.lua_get "call_count")
end

return T
