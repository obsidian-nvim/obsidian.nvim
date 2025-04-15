local util = require "obsidian.lsp.util"

local ns = vim.api.nvim_create_namespace "obsidian-ls.diagnostics"

-- IDEAD: inject markdownlint like none-ls
-- https://github.com/nvimtools/none-ls.nvim/blob/main/lua/null-ls/builtins/diagnostics/markdownlint.lua
-- https://github.com/nvimtools/none-ls.nvim/blob/main/lua/null-ls/builtins/diagnostics/markdownlint_cli2.lua

return function(client, params)
  local uri = params.textDocument.uri
  local buf = vim.uri_to_bufnr(uri)
  local diagnostics = {}

  local client_id = assert(vim.lsp.get_clients({ name = "obsidian-ls" })[1])

  local links = util.get_links(client, buf)

  for _, link in ipairs(links) do
    if link.target == "error" then
      table.insert(diagnostics, {
        lnum = link.range.start.line,
        col = link.range.start.character,
        severity = vim.lsp.protocol.DiagnosticSeverity.Warning,
        message = "This is an error",
        source = "obsidian-ls",
        code = "ERROR",
      })
    end
  end

  vim.diagnostic.set(ns, buf, diagnostics, { client_id = client_id })
end
