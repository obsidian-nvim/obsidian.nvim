local lsp = {}
local log = require "obsidian.log"

--- Check if a third-party completion engine (blink.cmp or nvim-cmp) is available.
--- Both engines auto-consume LSP completion from attached language servers.
---@return boolean
local function has_completion_engine()
  local has_blink = pcall(require, "blink.cmp")
  if has_blink then
    return true
  end
  local has_cmp = pcall(require, "cmp")
  if has_cmp then
    return true
  end
  return false
end

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

  local ok, client_id = pcall(vim.lsp.start, lsp_config, { bufnr = buf, silent = false })

  if not ok then
    log.err("[obsidian-ls]: failed to start: " .. client_id)
    return nil
  end

  -- Enable native completion for users without blink.cmp or nvim-cmp.
  -- vim.lsp.completion.enable() is available in Neovim >= 0.11.
  if vim.lsp.completion and vim.lsp.completion.enable and not has_completion_engine() then
    vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true })
    vim.api.nvim_create_autocmd("InsertCharPre", {
      buffer = buf,
      callback = function()
        vim.lsp.completion.get()
      end,
    })
  end

  ---@cast client_id integer
  return client_id
end

return lsp
