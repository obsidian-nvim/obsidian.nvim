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
        request = function(method, params, handler, _)
          handlers[method](params, handler, _)
        end,
        notify = function(method, params, handler, _)
          local self = vim.lsp.get_clients({ name = "obsidian-ls" })[1]
          -- handlers[method](params, handler, _)
          -- HACK: don't know why this needs to be here
          vim.api.nvim_exec_autocmds("LspNotify", {
            modeline = false,
            data = {
              client_id = self and self.id,
              method = method,
              params = params,
            },
          })
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
    log.err("[obsidian-ls]: faied to start: " .. client_id)
  end

  return client_id
end

return lsp
