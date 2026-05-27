local M = {}

local DIAGNOSTIC_SOURCE = "obsidian.nvim"

---@type table[]
local diagnostic_dispatchers = {}

---@type table<string, table<string, lsp.Diagnostic[]>>
local diagnostic_store = {}

---@param target integer|string buffer number, document URI, or file path
---@return string uri
---@return integer? version
local function diagnostic_target_uri(target)
  if type(target) == "number" then
    return vim.uri_from_bufnr(target), vim.api.nvim_buf_get_changedtick(target)
  end

  ---@cast target string
  if target:match "^%a[%w+.-]*:" then
    return target, nil
  end

  return vim.uri_from_fname(target), nil
end

---@param uri string
---@return lsp.Diagnostic[]
local function collect_diagnostics(uri)
  local by_source = diagnostic_store[uri]
  if not by_source then
    return {}
  end

  local sources = vim.tbl_keys(by_source)
  table.sort(sources)

  local diagnostics = {}
  for _, source in ipairs(sources) do
    for _, diagnostic in ipairs(by_source[source]) do
      diagnostics[#diagnostics + 1] = diagnostic
    end
  end
  return diagnostics
end

---@param diagnostics lsp.Diagnostic[]
---@param source string
---@return lsp.Diagnostic[]
local function normalize_diagnostics(diagnostics, source)
  local normalized = {}
  for _, diagnostic in ipairs(diagnostics) do
    local item = vim.tbl_extend("force", {}, diagnostic)
    item.source = item.source or source
    normalized[#normalized + 1] = item
  end
  return normalized
end

---@param uri string
---@param version integer?
---@return boolean published
local function publish_uri_diagnostics(uri, version)
  local params = {
    uri = uri,
    diagnostics = collect_diagnostics(uri),
  }

  if version then
    params.version = version
  end

  local published = false
  for _, dispatchers in ipairs(diagnostic_dispatchers) do
    if dispatchers.notification then
      dispatchers.notification("textDocument/publishDiagnostics", params)
      published = true
    end
  end

  return published
end

---@param dispatchers table
M.register_diagnostic_dispatchers = function(dispatchers)
  if not dispatchers or type(dispatchers.notification) ~= "function" then
    return
  end

  for _, existing in ipairs(diagnostic_dispatchers) do
    if existing == dispatchers then
      return
    end
  end

  diagnostic_dispatchers[#diagnostic_dispatchers + 1] = dispatchers

  for uri in pairs(diagnostic_store) do
    publish_uri_diagnostics(uri, nil)
  end
end

---@param dispatchers table
M.unregister_diagnostic_dispatchers = function(dispatchers)
  for i, existing in ipairs(diagnostic_dispatchers) do
    if existing == dispatchers then
      table.remove(diagnostic_dispatchers, i)
      return
    end
  end
end

---@class obsidian.lsp.PublishDiagnosticsOpts
---@field source string?
---@field version integer?

---Publish diagnostics for one producer. Replaces the previous diagnostics for
---the same target + source and then pushes the merged set to the LSP client.
---@param target integer|string buffer number, document URI, or file path
---@param diagnostics lsp.Diagnostic[]
---@param opts obsidian.lsp.PublishDiagnosticsOpts?
---@return boolean published true when at least one LSP client received the push
M.publish_diagnostics = function(target, diagnostics, opts)
  opts = opts or {}
  local source = opts.source or DIAGNOSTIC_SOURCE
  local uri, version = diagnostic_target_uri(target)
  diagnostic_store[uri] = diagnostic_store[uri] or {}
  diagnostic_store[uri][source] = normalize_diagnostics(diagnostics or {}, source)
  return publish_uri_diagnostics(uri, opts.version or version)
end

---@class obsidian.lsp.ClearDiagnosticsOpts
---@field source string?
---@field version integer?

---Clear diagnostics for a target. When opts.source is given, only that
---producer is cleared; otherwise all diagnostics for the target are cleared.
---@param target integer|string buffer number, document URI, or file path
---@param opts obsidian.lsp.ClearDiagnosticsOpts?
---@return boolean published true when at least one LSP client received the push
M.clear_diagnostics = function(target, opts)
  opts = opts or {}
  local uri, version = diagnostic_target_uri(target)

  if opts.source then
    if diagnostic_store[uri] then
      diagnostic_store[uri][opts.source] = nil
      if vim.tbl_isempty(diagnostic_store[uri]) then
        diagnostic_store[uri] = nil
      end
    end
  else
    diagnostic_store[uri] = nil
  end

  return publish_uri_diagnostics(uri, opts.version or version)
end

---@param opts { lnum: integer, col: integer, end_lnum: integer?, end_col: integer?, message: string, severity: integer?, source: string?, code: string|integer?, data: any? }
---@return lsp.Diagnostic
M.make_diagnostic = function(opts)
  return {
    range = {
      start = { line = opts.lnum, character = opts.col },
      ["end"] = { line = opts.end_lnum or opts.lnum, character = opts.end_col or (opts.col + 1) },
    },
    severity = opts.severity or vim.lsp.protocol.DiagnosticSeverity.Warning,
    source = opts.source or DIAGNOSTIC_SOURCE,
    code = opts.code,
    message = opts.message,
    data = opts.data,
  }
end

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
