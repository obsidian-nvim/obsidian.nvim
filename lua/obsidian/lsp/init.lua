local lsp = {}
local log = require "obsidian.log"

--- Start the lsp client
---
---@param buf integer
---@return integer?
lsp.start = function(buf)
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.workspace = capabilities.workspace or {}
  capabilities.workspace.fileOperations =
    vim.tbl_extend("force", capabilities.workspace.fileOperations or {}, { didRename = true })

  local lsp_config = {
    name = "obsidian-ls",
    capabilities = capabilities,
    offset_encoding = "utf-8",
    cmd = require "obsidian.lsp.server",
    init_options = {},
    root_dir = tostring(Obsidian.dir),
  }

  local client_id = vim.lsp.start(lsp_config, { bufnr = buf, silent = false })

  if not client_id then
    log.err("[obsidian-ls]: failed to start: " .. client_id)
    return
  end

  return client_id
end

return lsp
