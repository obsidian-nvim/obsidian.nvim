local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T.hooks = {
  pre_case = function()
    package.loaded["obsidian.lsp.watchfiles"] = nil
  end,
}

T["initialized"] = new_set()

T["initialized"]["should dynamically register markdown watcher"] = function()
  local handler = require "obsidian.lsp.handlers.initialized"
  local request_method, request_params
  local dispatchers = {
    server_request = function(method, params)
      request_method = method
      request_params = params
      return vim.NIL, nil
    end,
  }

  handler(vim.empty_dict(), dispatchers)

  eq("client/registerCapability", request_method)
  eq({
    registrations = {
      {
        id = "obsidian-watch-markdown",
        method = "workspace/didChangeWatchedFiles",
        registerOptions = {
          watchers = {
            {
              globPattern = "**/*.md",
              kind = vim.lsp.protocol.WatchKind.Create
                + vim.lsp.protocol.WatchKind.Change
                + vim.lsp.protocol.WatchKind.Delete,
            },
          },
        },
      },
    },
  }, request_params)
end

T["workspace/didChangeWatchedFiles"] = new_set()

T["workspace/didChangeWatchedFiles"]["should print normalized create and rename events"] = function()
  local handler = require "obsidian.lsp.handlers.did_change_watched_files"
  local original_print = vim.print
  local printed

  vim.print = function(value)
    printed = value
  end

  local old_uri = vim.uri_from_fname "/tmp/old.md"
  local new_uri = vim.uri_from_fname "/tmp/new.md"
  local create_uri = vim.uri_from_fname "/tmp/fresh.md"

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

  vim.print = original_print

  eq({
    {
      type = "renamed",
      old_path = "/tmp/old.md",
      old_uri = old_uri,
      new_path = "/tmp/new.md",
      new_uri = new_uri,
    },
    {
      type = "created",
      path = "/tmp/fresh.md",
      uri = create_uri,
    },
  }, printed)
end

T["workspace/didChangeWatchedFiles"]["should dispatch normalized events to registered handlers"] = function()
  local watchfiles = require "obsidian.lsp.watchfiles"
  local received_events, received_raw

  watchfiles.register_handler(function(events, raw_changes)
    received_events = events
    received_raw = raw_changes
  end)

  local changed_uri = vim.uri_from_fname "/tmp/watch.md"
  local raw_changes = {
    {
      uri = changed_uri,
      type = vim.lsp.protocol.FileChangeType.Changed,
    },
  }

  local events = watchfiles.handle(raw_changes)

  eq({
    {
      type = "changed",
      path = "/tmp/watch.md",
      uri = changed_uri,
    },
  }, events)
  eq(events, received_events)
  eq(raw_changes, received_raw)
end

T["lsp.start"] = new_set()

T["lsp.start"]["should enable dynamic watched files capability"] = function()
  local lsp = require "obsidian.lsp"
  local original_start = vim.lsp.start
  local captured_config

  vim.lsp.start = function(config)
    captured_config = config
    return 1
  end

  _G.Obsidian = _G.Obsidian or {}
  Obsidian.dir = "/tmp/obsidian-vault"

  lsp.start(1)

  vim.lsp.start = original_start

  eq(true, captured_config.capabilities.workspace.didChangeWatchedFiles.dynamicRegistration)
  eq(true, captured_config.capabilities.workspace.didChangeWatchedFiles.relativePatternSupport)
end

return T
