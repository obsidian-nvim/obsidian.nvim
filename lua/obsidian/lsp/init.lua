local lsp = {}

--- Start the lsp client
---
---@param client obsidian.Client
---@param buf integer
---@return integer
lsp.start = function(client, buf)
  local handlers = require "obsidian.lsp.handlers"
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  local client_id = vim.lsp.start({
    name = "obsidian-ls",
    capabilities = capabilities,
    cmd = function()
      return {
        request = function(method, params, handler, _)
          handlers[method](client, params, handler, _)
        end,
        notify = function(method, params, handler, _)
          handlers[method](client, params, handler, _)
        end,
        is_closing = function() end,
        terminate = function() end,
      }
    end,
    init_options = {},
    root_dir = tostring(Obsidian.dir),
  }, { bufnr = buf })
  assert(client_id, "failed to start obsidian_ls")

  return client_id
end

return lsp
