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
    offset_encoding = "utf-8",
    cmd = function()
      return {
        request = function(method, ...)
          local ok = pcall(handlers[method], ...)
          return ok
        end,
        notify = function(method, ...)
          local ok = pcall(handlers[method], ...)
          return ok
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

  local has_blink = pcall(require, "blink.cmp")
  local has_cmp = pcall(require, "cmp")

  if not (has_blink or has_cmp) and client_id then
    vim.lsp.completion.enable(true, client_id, buf, { autotrigger = true })
    vim.bo[buf].omnifunc = "v:lua.vim.lsp.omnifunc"
    vim.bo[buf].completeopt = "menu,menuone,noselect"
    vim.bo[buf].iskeyword = "@,48-57,192-255" -- HACK: so that completion for note names with `-` in it works in native completion
  end

  return client_id
end

return lsp
