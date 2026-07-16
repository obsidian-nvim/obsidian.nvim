local base_lsp = require "obsidian.base.lsp"

local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

local uri = vim.uri_from_fname "/tmp/example.base"

T["publishes parse and validation diagnostics"] = function()
  local notification
  base_lsp.handlers["textDocument/didOpen"]({
    textDocument = {
      uri = uri,
      text = "formulas:\n  bad: 10",
    },
  }, {
    notification = function(method, params)
      notification = { method = method, params = params }
    end,
  })

  eq("textDocument/publishDiagnostics", notification.method)
  eq(uri, notification.params.uri)
  eq(2, #notification.params.diagnostics)
  eq("base.missing-views", notification.params.diagnostics[1].code)
  eq("base.invalid-formula", notification.params.diagnostics[2].code)
end

T["offers a structural quick fix for a missing views section"] = function()
  local result
  base_lsp.handlers["textDocument/codeAction"]({
    textDocument = {
      uri = uri,
      text = "formulas:\n  title: file.name",
    },
    context = { diagnostics = {} },
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
  }, function(_, actions)
    result = actions
  end)

  eq(1, #result)
  eq("Add a table view", result[1].title)
  eq("\nviews:\n  - type: table\n    name: Table\n", result[1].edit.changes[uri][1].newText)
end

T["returns renderer-neutral document symbols"] = function()
  local result
  base_lsp.handlers["textDocument/documentSymbol"]({
    textDocument = {
      uri = uri,
      text = [[formulas:
  label: file.name
views:
  - type: table
    name: Table]],
    },
  }, function(_, symbols)
    result = symbols
  end)

  eq("Formulas", result[1].name)
  eq("label", result[1].children[1].name)
  eq("Table", result[2].name)
  eq("table", result[2].detail)
end

T["returns neutral results for Markdown-specific requests"] = function()
  local completion
  base_lsp.handlers["textDocument/completion"]({}, function(_, result)
    completion = result
  end)

  eq(false, completion.isIncomplete)
  eq({}, completion.items)
end

return T
