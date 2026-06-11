local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault [[
package.loaded["obsidian.lsp.watchfiles"] = nil
]]

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

T["didCreateFiles prompts for invalid filenames and renames to slug"] = function()
  child.lua [[
    local api = require "obsidian.api"
    local handler = require "obsidian.lsp.handlers.did_create_files"
    local uri = vim.uri_from_fname(vim.fs.joinpath(tostring(Obsidian.dir), "bad:name.md"))

    api.confirm = function(prompt, choices)
      _G.confirm_prompt = prompt
      _G.confirm_choices = choices
      return "Slug the name"
    end

    handler({ files = { { uri = uri } } }, {
      server_request = function(method, params)
        _G.request_method = method
        _G.request_label = params.label
        _G.document_change = params.edit.documentChanges[1]
      end,
    })
  ]]

  eq("Invalid filename", child.lua_get "confirm_prompt")
  eq("&Slug the name\n&Input a name", child.lua_get "confirm_choices")
  eq("workspace/applyEdit", child.lua_get "request_method")
  eq("Rename invalid filename", child.lua_get "request_label")
  eq("rename", child.lua_get "document_change.kind")
  eq(vim.uri_from_fname(tostring(child.Obsidian.dir / "badname.md")), child.lua_get "document_change.newUri")
end

T["didCreateFiles allows invalid filenames when global is set"] = function()
  child.lua [[
    vim.g.obsidian_allow_invalid_names = true
    local api = require "obsidian.api"
    local handler = require "obsidian.lsp.handlers.did_create_files"
    local uri = vim.uri_from_fname(vim.fs.joinpath(tostring(Obsidian.dir), "bad:name.md"))

    api.confirm = function()
      error "should not prompt"
    end

    handler({ files = { { uri = uri } } }, {
      server_request = function(method)
        _G.request_method = method
      end,
    })
  ]]

  eq(vim.NIL, child.lua_get "request_method")
end

T["didChangeWatchedFiles emits LSP create and delete events"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_change_watched_files"
    local results = {}
    local old_uri = vim.uri_from_fname "/tmp/old.md"
    local new_uri = vim.uri_from_fname "/tmp/new.md"
    local create_uri = vim.uri_from_fname "/tmp/fresh.md"

    require("obsidian.lsp.watchfiles").register_handler(function(events)
      for _, event in ipairs(events) do
        results[#results + 1] = event
      end
    end)

    handler {
      changes = {
        {
          uri = old_uri,
          type = vim.lsp.protocol.FileChangeType.Deleted,
        },
        {
          uri = new_uri,
          type = vim.lsp.protocol.FileChangeType.Created,
        },
        {
          uri = create_uri,
          type = vim.lsp.protocol.FileChangeType.Created,
        },
      },
    }

    _G.result_1 = results[1]
    _G.result_2 = results[2]
    _G.result_3 = results[3]
  ]]

  eq(vim.lsp.protocol.FileChangeType.Deleted, child.lua_get "result_1.type")
  eq(vim.uri_from_fname "/tmp/old.md", child.lua_get "result_1.uri")
  eq(vim.lsp.protocol.FileChangeType.Created, child.lua_get "result_2.type")
  eq(vim.uri_from_fname "/tmp/new.md", child.lua_get "result_2.uri")
  eq(vim.lsp.protocol.FileChangeType.Created, child.lua_get "result_3.type")
  eq(vim.uri_from_fname "/tmp/fresh.md", child.lua_get "result_3.uri")
end

T["watchfiles dispatches LSP events to registered handlers"] = function()
  child.lua [[
    local watchfiles = require "obsidian.lsp.watchfiles"
    local changed_uri = vim.uri_from_fname "/tmp/watch.md"

    watchfiles.register_handler(function(events, raw_changes)
      _G.received_event_type = events[1].type
      _G.received_event_uri = events[1].uri
      _G.received_raw_uri = raw_changes[1].uri
    end)

    local events = watchfiles.handle {
      {
        uri = changed_uri,
        type = vim.lsp.protocol.FileChangeType.Changed,
      },
    }

    _G.returned_event_type = events[1].type
    _G.returned_event_uri = events[1].uri
  ]]

  eq(vim.lsp.protocol.FileChangeType.Changed, child.lua_get "returned_event_type")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "returned_event_uri")
  eq(vim.lsp.protocol.FileChangeType.Changed, child.lua_get "received_event_type")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_event_uri")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_raw_uri")
end

T["watchfiles snapshots handlers while dispatching events"] = function()
  child.lua [[
    local watchfiles = require "obsidian.lsp.watchfiles"
    local calls = {}
    local unregister_first

    unregister_first = watchfiles.register_handler(function()
      calls[#calls + 1] = "first"
      unregister_first()
    end)

    watchfiles.register_handler(function()
      calls[#calls + 1] = "second"
    end)

    watchfiles.handle {
      {
        uri = vim.uri_from_fname "/tmp/watch.md",
        type = vim.lsp.protocol.FileChangeType.Changed,
      },
    }

    _G.first_call = calls[1]
    _G.second_call = calls[2]
  ]]

  eq("first", child.lua_get "first_call")
  eq("second", child.lua_get "second_call")
end

T["lsp.start enables dynamic watched files capability"] = function()
  child.lua [[
    local lsp = require "obsidian.lsp"
    local original_start = vim.lsp.start

    vim.lsp.start = function(config)
      _G.did_change_dynamic = config.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration
      _G.did_change_relative = config.capabilities.workspace.didChangeWatchedFiles.relativePatternSupport
      return 1
    end

    lsp.start(1)

    vim.lsp.start = original_start
  ]]

  eq(true, child.lua_get "did_change_dynamic")
  eq(true, child.lua_get "did_change_relative")
end

return T
