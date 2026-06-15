local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function run_folding_range()
  return h.child_await(
    child,
    [[
      local handler = require "obsidian.lsp.handlers.folding_range"
      handler({
        textDocument = { uri = vim.uri_from_bufnr(0) },
      }, function(_, res)
        done(res)
      end)
    ]],
    { desc = "foldingRange response", timeout = 2000 }
  )
end

T["uses note sections for heading folds"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["folds.md"] = [[---
title: Test
tags: [a]
aliases: x
more: y
fifth: z
---

# One
body
## Child
child body
# Two
```
# not a heading
```
tail]],
  })

  child.cmd("edit " .. files["folds.md"])

  eq({
    {
      startLine = 0,
      endLine = 6,
      kind = "imports",
      collapsedText = "Properties",
    },
    { startLine = 8, endLine = 11, kind = "region" },
    { startLine = 10, endLine = 11, kind = "region" },
    { startLine = 12, endLine = 16, kind = "region" },
  }, run_folding_range())
end

T["inherits setext heading support from sections"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["setext.md"] = [[Title
=====
body

Subtitle
--------
more]],
  })

  child.cmd("edit " .. files["setext.md"])

  eq({
    { startLine = 0, endLine = 6, kind = "region" },
    { startLine = 4, endLine = 6, kind = "region" },
  }, run_folding_range())
end

return T
