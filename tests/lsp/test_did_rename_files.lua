local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["initialize advertises didRenameFiles file operation support"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.initialize"

    handler(vim.empty_dict(), function(_, res)
      _G.did_rename_filter = res.capabilities.workspace.fileOperations.didRename.filters[1]
    end, {
      notification = function() end,
    })
  ]]

  eq("file", child.lua_get "did_rename_filter.scheme")
  eq("**/*.md", child.lua_get "did_rename_filter.pattern.glob")
  eq("file", child.lua_get "did_rename_filter.pattern.matches")
end

T["didRenameFiles applies reference edits without file rename"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_rename_files"
    local rename = require "obsidian.lsp.handlers._rename"
    local note_mod = require "obsidian.note"
    local api = require "obsidian.api"
    local Path = require "obsidian.path"
    local old_build_edit = rename.build_edit
    local old_from_file = note_mod.from_file
    local old_confirm = api.confirm

    note_mod.from_file = function(path)
      return {
        path = Path.new(path),
      }
    end

    rename.build_edit = function(note, new_name, opts)
      _G.captured_note_path = tostring(note.path)
      _G.captured_name = new_name
      _G.captured_old_path = opts.old_path
      _G.captured_new_path = opts.new_path
      _G.captured_include_file_rename = opts.include_file_rename
      return {
        documentChanges = {
          {
            textDocument = {
              uri = vim.uri_from_fname "/tmp/ref.md",
              version = vim.NIL,
            },
            edits = {},
          },
        },
      }, {
        count = 2,
        path_lookup = { ["/tmp/ref.md"] = true },
        buf_list = {},
        old_path = opts.old_path,
        new_path = opts.new_path,
      }
    end

    api.confirm = function(prompt)
      _G.confirm_prompt = prompt
      return "Yes"
    end

    handler({
      files = {
        {
          oldUri = vim.uri_from_fname "/tmp/folder/old.md",
          newUri = vim.uri_from_fname "/tmp/folder/new.md",
        },
      },
    }, {
      server_request = function(method, params)
        _G.request_method = method
        _G.request_label = params.label
      end,
    })

    rename.build_edit = old_build_edit
    note_mod.from_file = old_from_file
    api.confirm = old_confirm
  ]]

  eq("new", child.lua_get "captured_name")
  eq("/tmp/folder/new.md", child.lua_get "captured_note_path")
  eq("/tmp/folder/old.md", child.lua_get "captured_old_path")
  eq("/tmp/folder/new.md", child.lua_get "captured_new_path")
  eq(false, child.lua_get "captured_include_file_rename")
  eq("Update 2 reference(s) across 1 file(s) for renamed note 'new'?", child.lua_get "confirm_prompt")
  eq("workspace/applyEdit", child.lua_get "request_method")
  eq("Update renamed note references", child.lua_get "request_label")
end

T["didRenameFiles skips applyEdit when confirmation is declined"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_rename_files"
    local rename = require "obsidian.lsp.handlers._rename"
    local note_mod = require "obsidian.note"
    local api = require "obsidian.api"
    local Path = require "obsidian.path"
    local old_build_edit = rename.build_edit
    local old_from_file = note_mod.from_file
    local old_confirm = api.confirm

    _G.request_called = false

    note_mod.from_file = function(path)
      return {
        path = Path.new(path),
      }
    end

    rename.build_edit = function(_, _, opts)
      return {
        documentChanges = {
          {
            textDocument = {
              uri = vim.uri_from_fname "/tmp/ref.md",
              version = vim.NIL,
            },
            edits = {},
          },
        },
      }, {
        count = 1,
        path_lookup = { ["/tmp/ref.md"] = true },
        buf_list = {},
        old_path = opts.old_path,
        new_path = opts.new_path,
      }
    end

    api.confirm = function(prompt)
      _G.confirm_prompt = prompt
      return "No"
    end

    handler({
      files = {
        {
          oldUri = vim.uri_from_fname "/tmp/folder/old.md",
          newUri = vim.uri_from_fname "/tmp/folder/new.md",
        },
      },
    }, {
      server_request = function()
        _G.request_called = true
      end,
    })

    rename.build_edit = old_build_edit
    note_mod.from_file = old_from_file
    api.confirm = old_confirm
  ]]

  eq("Update 1 reference(s) across 1 file(s) for renamed note 'new'?", child.lua_get "confirm_prompt")
  eq(false, child.lua_get "request_called")
end

T["didRenameFiles skips confirmation when auto_update is enabled"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_rename_files"
    local rename = require "obsidian.lsp.handlers._rename"
    local note_mod = require "obsidian.note"
    local api = require "obsidian.api"
    local Path = require "obsidian.path"
    local old_build_edit = rename.build_edit
    local old_from_file = note_mod.from_file
    local old_confirm = api.confirm

    _G.request_called = false
    _G.confirm_called = false
    Obsidian.opts.link.auto_update = true

    note_mod.from_file = function(path)
      return {
        path = Path.new(path),
      }
    end

    rename.build_edit = function()
      return { documentChanges = {} }, {
        count = 0,
        path_lookup = {},
        buf_list = {},
        old_path = "",
        new_path = "",
      }
    end

    api.confirm = function()
      _G.confirm_called = true
      return "No"
    end

    handler({
      files = {
        {
          oldUri = vim.uri_from_fname "/tmp/folder/old.md",
          newUri = vim.uri_from_fname "/tmp/folder/new.md",
        },
      },
    }, {
      server_request = function()
        _G.request_called = true
      end,
    })

    Obsidian.opts.link.auto_update = false
    rename.build_edit = old_build_edit
    note_mod.from_file = old_from_file
    api.confirm = old_confirm
  ]]

  eq(false, child.lua_get "confirm_called")
  eq(true, child.lua_get "request_called")
end

return T
