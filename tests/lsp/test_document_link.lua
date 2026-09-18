local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function run_document_link()
  return h.child_await(
    child,
    [[
      local handler = require "obsidian.lsp.handlers.document_link"
      handler({
        textDocument = { uri = vim.uri_from_bufnr(0) },
      }, function(_, res)
        done(res)
      end)
    ]],
    { desc = "documentLink response", timeout = 2000 }
  )
end

T["resolves every link in the document"] = function()
  vim.fn.mkdir(tostring(child.Obsidian.dir / "notes"), "p")
  vim.fn.mkdir(tostring(child.Obsidian.dir / "attachments"), "p")
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["notes/target.md"] = "# target",
    ["attachments/img.png"] = "",
    ["doc.md"] = "# ref\n[[notes/target]]\n  [label](./notes/target.md)\n![alt](attachments/img.png)\nhttps://example.com\n[^1]",
  })

  child.cmd("edit " .. files["doc.md"])

  eq({
    {
      range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 16 } },
      target = vim.uri_from_fname(files["notes/target.md"]),
    },
    {
      range = { start = { line = 2, character = 2 }, ["end"] = { line = 2, character = 28 } },
      target = vim.uri_from_fname(files["notes/target.md"]),
    },
    {
      range = { start = { line = 3, character = 0 }, ["end"] = { line = 3, character = 27 } },
      target = vim.uri_from_fname(files["attachments/img.png"]),
    },
  }, run_document_link())
end

T["returns empty for documents without links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["plain.md"] = "# no links here",
  })

  child.cmd("edit " .. files["plain.md"])

  eq({}, run_document_link())
end

T["resolves links in unloaded buffers"] = function()
  vim.fn.mkdir(tostring(child.Obsidian.dir / "notes"), "p")
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["notes/target.md"] = "# target",
    ["unloaded.md"] = "[[notes/target]]",
  })

  local res = h.child_await(
    child,
    ([[
      local handler = require "obsidian.lsp.handlers.document_link"
      handler({ textDocument = { uri = %q } }, function(_, res)
        done(res)
      end)
    ]]):format(vim.uri_from_fname(files["unloaded.md"])),
    { desc = "documentLink response for unloaded buffer", timeout = 2000 }
  )

  eq({
    {
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 16 } },
      target = vim.uri_from_fname(files["notes/target.md"]),
    },
  }, res)
end

return T
