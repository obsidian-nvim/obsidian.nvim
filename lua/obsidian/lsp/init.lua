local lsp = {}
local log = require "obsidian.log"
local lsp_util = require "obsidian.lsp.util"

--- Start the lsp client
---
---@param buf integer
---@return integer?
lsp.start = function(buf)
  local capabilities = vim.lsp.protocol.make_client_capabilities()
  capabilities.workspace = capabilities.workspace or {}
  capabilities.workspace.fileOperations =
    vim.tbl_extend("force", capabilities.workspace.fileOperations or {}, { didRename = true, willDelete = true })
  -- manually enable dynamic registration for file watching, since neovim turns off this capability by default on linux and BSD
  capabilities.workspace.didChangeWatchedFiles = {
    dynamicRegistration = true,
    relativePatternSupport = true,
  }

  local lsp_config = {
    name = "obsidian-ls",
    capabilities = capabilities,
    offset_encoding = "utf-8",
    cmd = require "obsidian.lsp.server",
    init_options = {},
    root_dir = tostring(Obsidian.dir),
  }

  local warning = lsp_util.check_completion_availability()
  if warning then
    log.warn_once(warning)
  end

  local client_id = vim.lsp.start(lsp_config, { bufnr = buf, silent = false })

  if not client_id then
    log.err "[obsidian-ls]: failed to start"
    return
  end

  return client_id
end

return lsp
