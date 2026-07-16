local base = require "obsidian.base"

local M = {}

---@param params table?
---@return string?
local function params_uri(params)
  return params and params.textDocument and params.textDocument.uri or nil
end

---@param params table?
---@return boolean
function M.is_base_params(params)
  local uri = params_uri(params)
  return uri ~= nil and uri:lower():match "%.base$" ~= nil
end

---@param uri string
---@return string
local function buffer_source(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  end
  return ""
end

---@param params table
---@return string
local function params_source(params)
  if params.textDocument and type(params.textDocument.text) == "string" then
    return params.textDocument.text
  end
  local changes = params.contentChanges
  if changes and changes[#changes] and type(changes[#changes].text) == "string" then
    return changes[#changes].text
  end
  return buffer_source(assert(params_uri(params), "missing text document URI"))
end

---@param source string
---@return lsp.Range
local function document_range(source)
  local lines = vim.split(source, "\n", { plain = true })
  local last_line = math.max(#lines - 1, 0)
  return {
    start = { line = 0, character = 0 },
    ["end"] = { line = last_line, character = #(lines[#lines] or "") },
  }
end

---@param source string
---@param item obsidian.base.Diagnostic
---@return lsp.Diagnostic
local function lsp_diagnostic(source, item)
  local range = document_range(source)
  if item.line ~= nil then
    local lines = vim.split(source, "\n", { plain = true })
    local line = math.min(item.line, math.max(#lines - 1, 0))
    range = {
      start = { line = line, character = 0 },
      ["end"] = { line = line, character = #(lines[line + 1] or "") },
    }
  end
  return {
    range = range,
    severity = item.severity == "warning" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
    source = "obsidian-bases",
    code = item.code,
    message = item.path and (item.path .. ": " .. item.message) or item.message,
  }
end

---@param params table
---@param dispatchers table
local function publish_diagnostics(params, dispatchers)
  local uri = assert(params_uri(params), "missing text document URI")
  local source = params_source(params)
  local _, diagnostics = base.parse(source)
  local lsp_diagnostics = {}
  for _, item in ipairs(diagnostics) do
    lsp_diagnostics[#lsp_diagnostics + 1] = lsp_diagnostic(source, item)
  end
  dispatchers.notification("textDocument/publishDiagnostics", {
    uri = uri,
    diagnostics = lsp_diagnostics,
  })
end

---@param params lsp.DidCloseTextDocumentParams
---@param dispatchers table
local function clear_diagnostics(params, dispatchers)
  dispatchers.notification("textDocument/publishDiagnostics", {
    uri = params.textDocument.uri,
    diagnostics = {},
  })
end

---@param params lsp.DocumentSymbolParams
---@param handler function
local function document_symbols(params, handler)
  local source = params_source(params)
  local document = base.parse(source)
  if document == nil then
    return handler(nil, {})
  end

  local range = document_range(source)
  local symbols = {}
  local function container(name, children)
    if #children > 0 then
      symbols[#symbols + 1] = {
        name = name,
        kind = vim.lsp.protocol.SymbolKind.Namespace,
        range = range,
        selectionRange = range,
        children = children,
      }
    end
  end
  local function declarations(values)
    local children = {}
    for name in pairs(values) do
      children[#children + 1] = {
        name = name,
        kind = vim.lsp.protocol.SymbolKind.Function,
        range = range,
        selectionRange = range,
      }
    end
    table.sort(children, function(left, right)
      return left.name < right.name
    end)
    return children
  end

  container("Formulas", declarations(document.formulas))
  local property_symbols = {}
  for name in pairs(document.properties) do
    property_symbols[#property_symbols + 1] = {
      name = name,
      kind = vim.lsp.protocol.SymbolKind.Property,
      range = range,
      selectionRange = range,
    }
  end
  table.sort(property_symbols, function(left, right)
    return left.name < right.name
  end)
  container("Properties", property_symbols)
  container("Summaries", declarations(document.summaries))

  for index, view in ipairs(document.views) do
    symbols[#symbols + 1] = {
      name = view.name or ("View " .. index),
      detail = view.type,
      kind = vim.lsp.protocol.SymbolKind.Object,
      range = range,
      selectionRange = range,
    }
  end
  handler(nil, symbols)
end

---@param params lsp.CodeActionParams
---@param handler function
local function code_actions(params, handler)
  local uri = assert(params_uri(params), "missing text document URI")
  local source = params_source(params)
  local _, diagnostics = base.parse(source)
  local missing_views = false
  for _, item in ipairs(diagnostics) do
    if item.code == "base.missing-views" then
      missing_views = true
      break
    end
  end
  if not missing_views then
    return handler(nil, {})
  end

  local range = document_range(source)
  local prefix = (source == "" or source:sub(-1) == "\n") and "" or "\n"
  handler(nil, {
    {
      title = "Add a table view",
      kind = "quickfix",
      edit = {
        changes = {
          [uri] = {
            {
              range = { start = range["end"], ["end"] = range["end"] },
              newText = prefix .. "views:\n  - type: table\n    name: Table\n",
            },
          },
        },
      },
    },
  })
end

local function empty_list(_, handler)
  handler(nil, {})
end

local function empty_completion(_, handler)
  handler(nil, { isIncomplete = false, items = {} })
end

local function empty_result(_, handler)
  handler(nil, nil)
end

M.handlers = {
  ["textDocument/didOpen"] = publish_diagnostics,
  ["textDocument/didChange"] = publish_diagnostics,
  ["textDocument/didClose"] = clear_diagnostics,
  ["textDocument/documentSymbol"] = document_symbols,
  ["textDocument/codeAction"] = code_actions,
  ["textDocument/completion"] = empty_completion,
  ["textDocument/foldingRange"] = empty_list,
  ["textDocument/definition"] = empty_result,
  ["textDocument/references"] = empty_list,
  ["textDocument/prepareRename"] = empty_result,
  ["textDocument/rename"] = empty_result,
}

return M
