local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function highlight(line, character)
  return h.child_await(
    child,
    ([[
      require("obsidian.lsp.handlers.document_highlight")({
        textDocument = { uri = vim.uri_from_bufnr(0) },
        position = { line = %d, character = %d },
      }, function(_, res)
        done(res)
      end)
    ]]):format(line, character),
    { desc = "documentHighlight response" }
  )
end

local function expected(line, start_character, end_character)
  return {
    {
      range = {
        start = { line = line, character = start_character },
        ["end"] = { line = line, character = end_character },
      },
      kind = vim.lsp.protocol.DocumentHighlightKind.Text,
    },
  }
end

T["advertises and registers document highlights"] = function()
  local result = child.lua [[
    local initialize = require "obsidian.lsp.handlers.initialize"
    local response
    initialize({}, function(_, res)
      response = res
    end, { notification = function() end })
    return {
      provider = response.capabilities.documentHighlightProvider,
      registered = require("obsidian.lsp.handlers")["textDocument/documentHighlight"] ~= nil,
    }
  ]]

  eq({ provider = true, registered = true }, result)
end

T["highlights scalar frontmatter tags"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["scalar.md"] = "---\ntags: alpha\n---\n#alpha",
  })
  child.cmd("edit " .. files["scalar.md"])

  eq(expected(1, 6, 11), highlight(1, 8))
end

T["highlights individual flow-list tags with UTF-8 byte ranges"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["flow.md"] = "---\ntags: [one, 'café', two]\n---",
  })
  child.cmd("edit " .. files["flow.md"])

  eq(expected(1, 7, 10), highlight(1, 8))
  eq(expected(1, 13, 18), highlight(1, 16))
  eq(expected(1, 21, 24), highlight(1, 22))
end

T["highlights block-list tag names without YAML decoration"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["block.md"] = "---\ntags:\n  - alpha\n  - '#beta'\n---",
  })
  child.cmd("edit " .. files["block.md"])

  eq(expected(2, 4, 9), highlight(2, 6))
  eq(expected(3, 6, 10), highlight(3, 7))
  eq({}, highlight(3, 4)) -- quote
  eq({}, highlight(3, 5)) -- optional leading '#'
end

T["ignores keys, unrelated values, delimiters, and body tags"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["negative.md"] = "---\ntags: [alpha]\ntitle: alpha\n---\n#alpha",
  })
  child.cmd("edit " .. files["negative.md"])

  eq({}, highlight(0, 1))
  eq({}, highlight(1, 2))
  eq({}, highlight(2, 8))
  eq({}, highlight(3, 1))
  eq({}, highlight(4, 2))
end

T["returns no highlights for invalid frontmatter"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["invalid.md"] = "---\ntags: [alpha]\nbroken: {\n---",
  })
  child.cmd("edit " .. files["invalid.md"])

  eq({}, highlight(1, 8))
end

return T
