local lsp = {}
local log = require "obsidian.log"

local function check_completion_availability()
  if pcall(require, "blink.cmp") then
    local blink_markdown_config = require("blink.cmp.config").sources.per_filetype["markdown"]
    if not blink_markdown_config then
      return
    end
    if type(blink_markdown_config) == "function" then
      blink_markdown_config = blink_markdown_config()
    end
    local configured = vim.tbl_contains(blink_markdown_config, "lsp") or blink_markdown_config.inherit_defaults
    if not configured then
      log.warn [[This plugin has migrated to in process lsp completion, blink.cmp config for markdown buffer is not properly configured, add
```lua
require("blink.cmp").setup({
   per_filetype = {
      markdown = { 
         inherit_defaults = true, 
         -- or
         "lsp"
      },
   },
})
```
      ]]
    end
  elseif pcall(require, "cmp") then
    if not pcall(require, "cmp_nvim_lsp") then
      log.warn [[This plugin has migrated to in process lsp completion, for your nvim-cmp setup you need cmp-nvim-lsp plugin]]
      return
    end
    local cmp_config = require "cmp.config"
    local ft_conf = cmp_config.filetypes["markdown"]
    local sources = (ft_conf and ft_conf.sources) or (cmp_config.global and cmp_config.global.sources) or {}
    local configured = false
    for _, src in ipairs(sources) do
      if src.name == "nvim_lsp" then
        configured = true
        break
      end
    end
    if not configured then
      log.warn [[This plugin has migrated to in process lsp completion, nvim-cmp source `nvim_lsp` is not configured for markdown buffers, add
```lua
require("cmp").setup({
  sources = {
    { name = "nvim_lsp" },
  },
})
-- or per-filetype:
require("cmp").setup.filetype("markdown", {
  sources = {
    { name = "nvim_lsp" },
  },
})
```
      ]]
    end
  end
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

  check_completion_availability()

  local client_id = vim.lsp.start(lsp_config, { bufnr = buf, silent = false })

  if not client_id then
    log.err "[obsidian-ls]: failed to start"
    return
  end

  return client_id
end

return lsp
