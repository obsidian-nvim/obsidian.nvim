local log = require "obsidian.log"

local WatchKind = vim.lsp.protocol.WatchKind

local EMBED_EXTENSIONS = table.concat({
  "markdown",
  "qmd",
  "base",
  unpack(require("obsidian.attachment").filetypes),
}, ",")

local registration = {
  registrations = {
    {
      id = "obsidian-watch-vault",
      method = "workspace/didChangeWatchedFiles",
      registerOptions = {
        watchers = {
          {
            globPattern = "**/*.{" .. EMBED_EXTENSIONS .. "}",
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
