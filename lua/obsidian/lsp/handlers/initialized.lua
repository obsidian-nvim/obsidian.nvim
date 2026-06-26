local log = require "obsidian.log"
local attachment = require "obsidian.attachment"

local WatchKind = vim.lsp.protocol.WatchKind

local function watched_filetypes()
  local seen = { markdown = true, qmd = true, base = true }
  for _, ext in ipairs(attachment.filetypes) do
    seen[ext] = true
  end
  local exts = vim.tbl_keys(seen)
  table.sort(exts)
  return exts
end

local function watcher_registration()
  local watchers = {}
  for _, ext in ipairs(watched_filetypes()) do
    watchers[#watchers + 1] = {
      globPattern = "**/*." .. ext,
      kind = WatchKind.Create + WatchKind.Change + WatchKind.Delete,
    }
  end

  return {
    registrations = {
      {
        id = "obsidian-watch-files",
        method = "workspace/didChangeWatchedFiles",
        registerOptions = {
          watchers = watchers,
        },
      },
    },
  }
end

return function(_, dispatchers)
  local _, err = dispatchers.server_request("client/registerCapability", watcher_registration())
  if err then
    log.err("[obsidian-ls] failed to register file watcher: %s", err)
  end
end
