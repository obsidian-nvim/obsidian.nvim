local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault [[
package.loaded["obsidian.lsp.watchfiles"] = nil
]]

T["initialize advertises didSave synchronization"] = function()
  child.lua [[
    require("obsidian.lsp.handlers.initialize")({}, function(_, result)
      _G.did_save_sync = result.capabilities.textDocumentSync.save
    end, {
      notification = function() end,
    })
  ]]

  eq(true, child.lua_get "did_save_sync")
end

T["saving an attached note emits didSave"] = function()
  child.lua [[
    local path = vim.fs.joinpath(tostring(Obsidian.dir), "saved.md")
    vim.fn.writefile({ "#one" }, path)

    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    assert(vim.wait(1000, cache.is_ready))

    local refresh = cache.notes.refresh
    local refreshes = 0
    local inlay_refreshes = 0
    cache.notes.refresh = function(saved_path)
      refreshes = refreshes + 1
      refresh(saved_path)
    end
    local original_inlay_refresh = vim.lsp.handlers["workspace/inlayHint/refresh"]
    vim.lsp.handlers["workspace/inlayHint/refresh"] = function()
      inlay_refreshes = inlay_refreshes + 1
      return vim.NIL
    end

    vim.cmd("edit " .. vim.fn.fnameescape(path))
    assert(vim.wait(1000, function()
      local clients = vim.lsp.get_clients { bufnr = 0, name = "obsidian-ls" }
      return clients[1] ~= nil and clients[1].initialized
    end))

    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "#two" })
    vim.cmd "write"
    assert(vim.wait(1000, function()
      return refreshes > 0 and inlay_refreshes > 0
    end))

    vim.lsp.handlers["workspace/inlayHint/refresh"] = original_inlay_refresh
    _G.did_save_refreshes = refreshes
    _G.did_save_inlay_refreshes = inlay_refreshes
    _G.did_save_tags = cache.notes.find(path).tags
  ]]

  eq(1, child.lua_get "did_save_refreshes")
  eq(1, child.lua_get "did_save_inlay_refreshes")
  eq({ "two" }, child.lua_get "did_save_tags")
end

T["initialized dynamically registers file watchers"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.initialized"

    handler(vim.empty_dict(), {
      server_request = function(method, params)
        _G.request_method = method
        _G.request_id = params.registrations[1].id
        _G.request_watch_method = params.registrations[1].method
        _G.request_watchers = params.registrations[1].registerOptions.watchers
        return vim.NIL, nil
      end,
    })
  ]]

  eq("client/registerCapability", child.lua_get "request_method")
  eq("obsidian-watch-files", child.lua_get "request_id")
  eq("workspace/didChangeWatchedFiles", child.lua_get "request_watch_method")

  local watchers = child.lua_get "request_watchers"
  local glob_to_kind = {}
  for _, watcher in ipairs(watchers) do
    glob_to_kind[watcher.globPattern] = watcher.kind
  end

  eq(
    vim.lsp.protocol.WatchKind.Create + vim.lsp.protocol.WatchKind.Change + vim.lsp.protocol.WatchKind.Delete,
    glob_to_kind["**/*.md"]
  )
  eq(
    vim.lsp.protocol.WatchKind.Create + vim.lsp.protocol.WatchKind.Change + vim.lsp.protocol.WatchKind.Delete,
    glob_to_kind["**/*.png"]
  )
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
    _G.returned_event_uri = events[1].uri
    _G.returned_event_path = events[1].path
  ]]

  eq(vim.lsp.protocol.FileChangeType.Changed, child.lua_get "returned_event_type")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "returned_event_uri")
  eq("/tmp/watch.md", child.lua_get "returned_event_path")
  eq(vim.lsp.protocol.FileChangeType.Changed, child.lua_get "received_event_type")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_event_uri")
  eq("/tmp/watch.md", child.lua_get "received_event_path")
  eq(vim.uri_from_fname "/tmp/watch.md", child.lua_get "received_raw_uri")
end

T["watchfiles normalizes URI paths"] = function()
  child.lua [[
    local watchfiles = require "obsidian.lsp.watchfiles"
    local uri = "file:///C:/tmp/watch.md"

    watchfiles.register_handler(function(events, raw_changes)
      _G.received_path = events[1].path
      _G.raw_has_path = raw_changes[1].path ~= nil
    end)

    local events = watchfiles.handle {
      {
        uri = uri,
        type = vim.lsp.protocol.FileChangeType.Changed,
      },
    }

    _G.expected_path = vim.fs.normalize(vim.uri_to_fname(uri))
    _G.returned_path = events[1].path
  ]]

  eq(child.lua_get "expected_path", child.lua_get "returned_path")
  eq(child.lua_get "expected_path", child.lua_get "received_path")
  eq(false, child.lua_get "raw_has_path")
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
