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

T["does not refresh backlinks for non-note or hidden file events"] = function()
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

    local watchfiles = require "obsidian.lsp.watchfiles"
    local function fire(p)
      watchfiles.handle { {
        path = p,
        type = vim.lsp.protocol.FileChangeType.Changed,
      } }
    end

    fire(vim.fs.joinpath(tostring(Obsidian.dir), "image.png"))
    _G.calls_after_png = #calls
    fire(vim.fs.joinpath(tostring(Obsidian.dir), ".conform.123.current.md"))
    _G.calls_after_hidden = #calls
    fire(vim.fs.joinpath(tostring(Obsidian.dir), "other.md"))
    _G.calls_after_note = #calls
    _G.note_update_backlinks = calls[#calls]
    watchfiles.handle { {
      old_path = vim.fs.joinpath(tostring(Obsidian.dir), "old.md"),
      new_path = vim.fs.joinpath(tostring(Obsidian.dir), "new.md"),
      type = vim.lsp.protocol.FileChangeType.Changed,
    } }
    _G.calls_after_rename = #calls
    _G.rename_update_backlinks = calls[#calls]

    Note.status = original_status
    vim.schedule = original_schedule
  ]]

  eq(1, child.lua_get "calls_after_png")
  eq(1, child.lua_get "calls_after_hidden")
  eq(2, child.lua_get "calls_after_note")
  eq(true, child.lua_get "note_update_backlinks")
  eq(3, child.lua_get "calls_after_rename")
  eq(true, child.lua_get "rename_update_backlinks")
end

T["event filter ignores hidden components above the workspace root"] = function()
  child.lua [[
    local Path = require "obsidian.path"
    -- A workspace root under a dot-prefixed directory, derived from the test
    -- vault's (existing) parent so that path resolution behaves the same on
    -- every platform.
    local root = Path.new(vim.fs.joinpath(vim.fs.dirname(tostring(Obsidian.dir)), ".vaults", "main")):resolve()
    local ws = { root = root, name = "main" }
    local affects = require("obsidian.footer")._event_affects_backlinks

    _G.note_in_dotdir_vault = affects({ path = vim.fs.joinpath(tostring(root), "note.md") }, ws)
    _G.hidden_file_in_vault = affects({ path = vim.fs.joinpath(tostring(root), ".conform.1.note.md") }, ws)
    _G.hidden_dir_in_vault = affects({ path = vim.fs.joinpath(tostring(root), ".trash", "note.md") }, ws)
    _G.non_note_in_vault = affects({ path = vim.fs.joinpath(tostring(root), "image.png") }, ws)
    _G.outside_workspace =
      affects({ path = vim.fs.joinpath(vim.fs.dirname(tostring(Obsidian.dir)), "elsewhere", "note.md") }, ws)
  ]]

  eq(true, child.lua_get "note_in_dotdir_vault")
  eq(false, child.lua_get "hidden_file_in_vault")
  eq(false, child.lua_get "hidden_dir_in_vault")
  eq(false, child.lua_get "non_note_in_vault")
  eq(false, child.lua_get "outside_workspace")
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
