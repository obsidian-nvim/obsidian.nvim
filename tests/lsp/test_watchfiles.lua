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

T["didChangeWatchedFiles normalizes create and rename events"] = function()
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
  ]]

  eq("renamed", child.lua_get "result_1.type")
  eq("/tmp/old.md", child.lua_get "result_1.old_path")
  eq(vim.uri_from_fname "/tmp/old.md", child.lua_get "result_1.old_uri")
  eq("/tmp/new.md", child.lua_get "result_1.new_path")
  eq(vim.uri_from_fname "/tmp/new.md", child.lua_get "result_1.new_uri")
  eq("created", child.lua_get "result_2.type")
  eq("/tmp/fresh.md", child.lua_get "result_2.path")
  eq(vim.uri_from_fname "/tmp/fresh.md", child.lua_get "result_2.uri")
end

T["watchfiles dispatches normalized events to registered handlers"] = function()
  child.lua [[
    local watchfiles = require "obsidian.lsp.watchfiles"
    local changed_uri = vim.uri_from_fname "/tmp/watch.md"

    watchfiles.register_handler(function(events, raw_changes)
      _G.received_event_type = events[1].type
      _G.received_event_path = events[1].path
      _G.received_raw_uri = raw_changes[1].uri
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
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_raw_uri")
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
