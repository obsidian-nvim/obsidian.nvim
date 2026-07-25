local log = require "obsidian.log"
local filetypes = require "obsidian.filetypes"

local WatchKind = vim.lsp.protocol.WatchKind

return function(_, dispatchers)
  local watchers = {
    {
      globPattern = filetypes.glob(filetypes.note_extensions),
      kind = WatchKind.Create + WatchKind.Change + WatchKind.Delete,
    },
  }
  if Obsidian.opts.cache.enabled then
    watchers[#watchers + 1] = {
      globPattern = filetypes.glob(filetypes.attachment_extensions),
      kind = WatchKind.Create + WatchKind.Change + WatchKind.Delete,
    }
  end

  local registration = {
    registrations = {
      {
        id = "obsidian-watch-vault-files",
        method = "workspace/didChangeWatchedFiles",
        registerOptions = {
          watchers = watchers,
        },
      },
    },
  }
  local _, err = dispatchers.server_request("client/registerCapability", registration)
  if err then
    log.err("[obsidian-ls] failed to register vault file watcher: %s", err)
  end
end
