local log = require "obsidian.log"

local WatchKind = vim.lsp.protocol.WatchKind

local registration = {
  registrations = {
    {
      id = "obsidian-watch-markdown",
      method = "workspace/didChangeWatchedFiles",
      registerOptions = {
        watchers = {
          {
            globPattern = "**/*.md",
            kind = WatchKind.Create + WatchKind.Change + WatchKind.Delete,
          },
        },
      },
    },
  },
}

return function(_, dispatchers)
  local _, err = dispatchers.server_request("client/registerCapability", registration)
  if err then
    log.err("[obsidian-ls] failed to register markdown file watcher: %s", err)
  end
end
