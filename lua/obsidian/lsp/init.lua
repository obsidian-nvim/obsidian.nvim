local lsp = {}
local log = require "obsidian.log"

--- Start the lsp client
---
---@param buf integer
---@return integer?
lsp.start = function(buf)
  local handlers = require "obsidian.lsp.handlers"
  local capabilities = vim.lsp.protocol.make_client_capabilities()

  local lsp_config = {
    name = "obsidian-ls",
    capabilities = capabilities,
    cmd = function()
      return {
        request = function(method, ...)
          handlers[method](...)
        end,
        notify = function(method, ...)
          handlers[method](...)
        end,
        is_closing = function() end,
        terminate = function() end,
      }
    end,
    init_options = {},
    root_dir = tostring(Obsidian.dir),
  }

  local ok, client_id = pcall(vim.lsp.start, lsp_config, { bufnr = buf, silent = false })

  if not ok then
    log.err("[obsidian-ls]: failed to start: " .. client_id)
  end

  return client_id
end

return lsp
