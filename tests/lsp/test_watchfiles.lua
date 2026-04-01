local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault [[
package.loaded["obsidian.lsp.watchfiles"] = nil
package.loaded["obsidian.lsp.handlers.did_rename_files"] = nil
Obsidian.opts.link.auto_update = false
]]

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

T["initialized dynamically registers markdown watcher"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.initialized"

    handler(vim.empty_dict(), {
      server_request = function(method, params)
        _G.request_method = method
        _G.request_id = params.registrations[1].id
        _G.request_watch_method = params.registrations[1].method
        _G.request_watch_glob = params.registrations[1].registerOptions.watchers[1].globPattern
        _G.request_watch_kind = params.registrations[1].registerOptions.watchers[1].kind
        return vim.NIL, nil
      end,
    })
  ]]

  eq("client/registerCapability", child.lua_get "request_method")
  eq("obsidian-watch-markdown", child.lua_get "request_id")
  eq("workspace/didChangeWatchedFiles", child.lua_get "request_watch_method")
  eq("**/*.md", child.lua_get "request_watch_glob")
  eq(
    vim.lsp.protocol.WatchKind.Create + vim.lsp.protocol.WatchKind.Change + vim.lsp.protocol.WatchKind.Delete,
    child.lua_get "request_watch_kind"
  )
end

T["didChangeWatchedFiles prints normalized raw file events"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_change_watched_files"
    local original_print = vim.print
    local create_uri = vim.uri_from_fname "/tmp/fresh.md"
    local delete_uri = vim.uri_from_fname "/tmp/gone.md"

    vim.print = function(value)
      _G.printed_events = value
    end

    handler {
      changes = {
        {
          uri = create_uri,
          type = vim.lsp.protocol.FileChangeType.Created,
        },
        {
          uri = delete_uri,
          type = vim.lsp.protocol.FileChangeType.Deleted,
        },
      },
    }

    vim.print = original_print
  ]]

  eq("created", child.lua_get "printed_events[1].type")
  eq("/tmp/fresh.md", child.lua_get "printed_events[1].path")
  eq(vim.uri_from_fname "/tmp/fresh.md", child.lua_get "printed_events[1].uri")
  eq("deleted", child.lua_get "printed_events[2].type")
  eq("/tmp/gone.md", child.lua_get "printed_events[2].path")
  eq(vim.uri_from_fname "/tmp/gone.md", child.lua_get "printed_events[2].uri")
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
  eq("Update links to renamed note 'new'?", child.lua_get "confirm_prompt")
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

    rename.build_edit = function()
      return { documentChanges = {} }
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

  eq("Update links to renamed note 'new'?", child.lua_get "confirm_prompt")
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
      return { documentChanges = {} }
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

T["watchfiles dispatches normalized events to registered handlers"] = function()
  child.lua [[
    local watchfiles = require "obsidian.lsp.watchfiles"
    local changed_uri = vim.uri_from_fname "/tmp/watch.md"

    watchfiles.register_handler(function(events, payload, source)
      _G.received_event_type = events[1].type
      _G.received_event_path = events[1].path
      _G.received_payload_uri = payload[1].uri
      _G.received_source = source
    end)

    local events = watchfiles.handle {
      {
        uri = changed_uri,
        type = vim.lsp.protocol.FileChangeType.Changed,
      },
    }

    _G.returned_event_type = events[1].type
    _G.returned_event_path = events[1].path
  ]]

  eq("changed", child.lua_get "returned_event_type")
  eq("/tmp/watch.md", child.lua_get "returned_event_path")
  eq("changed", child.lua_get "received_event_type")
  eq("/tmp/watch.md", child.lua_get "received_event_path")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_payload_uri")
  eq("workspace/didChangeWatchedFiles", child.lua_get "received_source")
end

T["lsp.start enables watched files and didRename capabilities"] = function()
  child.lua [[
    local lsp = require "obsidian.lsp"
    local original_start = vim.lsp.start

    vim.lsp.start = function(config)
      _G.did_change_dynamic = config.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration
      _G.did_change_relative = config.capabilities.workspace.didChangeWatchedFiles.relativePatternSupport
      _G.did_rename = config.capabilities.workspace.fileOperations.didRename
      return 1
    end

    lsp.start(1)

    vim.lsp.start = original_start
  ]]

  eq(true, child.lua_get "did_change_dynamic")
  eq(true, child.lua_get "did_change_relative")
  eq(true, child.lua_get "did_rename")
end

return T
