local M = require "obsidian.completion.sources.search"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local bufnr = vim.api.nvim_create_buf(false, true)
vim.b[bufnr].obsidian_completion_source = "search_query"

local function complete(before, after)
  local result
  M.process_completion(function(response)
    result = response
  end, {
    bufnr = bufnr,
    cursor_before_line = before,
    cursor_after_line = after or "",
    line = 0,
    character = #before,
  })
  return assert(result, "completion source did not respond")
end

T["completes search operator prefixes"] = function()
  local cases = {
    { "pa", "path:" },
    { "fi", "file:" },
    { "li", "line:" },
    { "se", "section:" },
    { "ta", "tag:" },
    { "[", "[property]" },
  }

  for _, case in ipairs(cases) do
    local result = complete(case[1])
    eq(1, #result.items)
    eq(case[2], result.items[1].label)
    eq(case[2], result.items[1].textEdit.newText)
  end
end

T["replaces only the current expression prefix"] = function()
  local item = complete("content:needle OR se").items[1]
  eq("section:", item.label)
  eq(18, item.textEdit.range.start.character)
  eq(20, item.textEdit.range["end"].character)

  item = complete("-fi").items[1]
  eq("file:", item.label)
  eq(1, item.textEdit.range.start.character)
  eq(3, item.textEdit.range["end"].character)

  item = complete("pa", "th:").items[1]
  eq("path:", item.label)
  eq(0, item.textEdit.range.start.character)
  eq(5, item.textEdit.range["end"].character)
end

T["does not complete in an ordinary buffer"] = function()
  vim.b[bufnr].obsidian_completion_source = nil
  eq({}, complete("pa").items)
  vim.b[bufnr].obsidian_completion_source = "search_query"
end

T["the LSP completion handler dispatches to the search source"] = function()
  vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. ".md")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "pa" })

  local result
  require "obsidian.lsp.handlers.completion"({
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = 0, character = 2 },
  }, function(_, response)
    result = response
  end)

  eq("path:", assert(result, "completion handler did not respond").items[1].label)
end

return T
