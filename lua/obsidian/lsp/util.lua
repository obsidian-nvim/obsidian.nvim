local M = {}

---@return string|?
M.check_completion_availability = function()
  if pcall(require, "blink.cmp") then
    local blink_config = require("blink.cmp.config").sources.default
    local blink_markdown_config = require("blink.cmp.config").sources.per_filetype["markdown"]
    if not blink_markdown_config then
      return
    end
    if type(blink_markdown_config) == "function" then
      blink_markdown_config = blink_markdown_config()
    end
    if type(blink_config) == "function" then
      blink_config = blink_config()
    end
    local configured = vim.tbl_contains(blink_markdown_config, "lsp")
      or (blink_markdown_config.inherit_defaults and vim.tbl_contains(blink_config, "lsp"))
    if not configured then
      return [[This plugin has migrated to in process lsp completion, blink.cmp config for markdown buffer is not properly configured, add
```lua
require("blink.cmp").setup({
   per_filetype = {
      markdown = {
         "lsp"
         -- or if "lsp" in defaults
         inherit_defaults = true,
      },
   },
})
```
]]
    end
  elseif pcall(require, "cmp") then
    if not pcall(require, "cmp_nvim_lsp") then
      return [[This plugin has migrated to in process lsp completion, for your nvim-cmp setup you need cmp-nvim-lsp plugin]]
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
      return [[This plugin has migrated to in process lsp completion, nvim-cmp source `nvim_lsp` is not configured for markdown buffers, add
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

return M
