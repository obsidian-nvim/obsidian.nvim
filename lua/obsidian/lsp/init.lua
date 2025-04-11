-- reference: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
-- reference: https://github.com/zk-org/zk/blob/main/internal/adapter/lsp/server.go
local obsidian_client = require("obsidian").get_client()
local handlers = require "obsidian.lsp.handlers"

local obsidian_ls = {}
local capabilities = vim.lsp.protocol.make_client_capabilities()
local has_blink, blink = pcall(require, "blink.cmp")
if has_blink then
  capabilities = blink.get_lsp_capabilities({}, true)
end

---@return integer? client_id
obsidian_ls.start = function()
  local client_id = vim.lsp.start {
    name = "obsidian-ls",
    capabilities = capabilities,
    cmd = function(dispatchers)
      local _ = dispatchers
      local members = {
        request = function(method, params, handler, _)
          print(method)
          handlers[method](method, params, handler, _)
        end,
        notify = function() end, -- Handle notify events
        is_closing = function() end,
        terminate = function() end,
      }
      return members
    end,
    init_options = {},
    root_dir = tostring(obsidian_client.dir),
  }
  return client_id
end

return obsidian_ls
