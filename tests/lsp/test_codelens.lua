local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function lenses()
  return h.child_await(
    child,
    [[
    require("obsidian.lsp.handlers.codelens")({
      textDocument = { uri = vim.uri_from_bufnr(0) },
    }, function(err, result)
      assert(err == nil)
      done(result)
    end)
  ]],
    { desc = "section code lenses" }
  )
end

T["shows word counts for unreferenced sections, excluding titles and children"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = [[---
title: ignored
---
Preamble
# Parent
one two
## Child
three
# Empty
]],
  })
  child.cmd("edit " .. files["target.md"])

  local result = lenses()
  eq(3, #result)
  eq(
    { "2 words", "1 word", "0 words" },
    vim.tbl_map(function(lens)
      return lens.command.title
    end, result)
  )
  eq(
    { 4, 6, 8 },
    vim.tbl_map(function(lens)
      return lens.range.start.line
    end, result)
  )
  eq({ vim.uri_from_fname(files["target.md"]), 4, "#parent" }, result[1].command.arguments)

  -- Word counts must use the current buffer, not the saved file.
  child.api.nvim_buf_set_lines(0, 5, 6, false, { "one two four" })
  eq("3 words", lenses()[1].command.title)
end

T["shows backlink counts only for referenced headings"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = [[# Referenced
body text
## Unreferenced
child text
# Another
last]],
    ["source.md"] = [=[[[target#Referenced]]
[again](target.md#Referenced)
[[target#Another]]]=],
  })
  child.cmd("edit " .. files["target.md"])

  local result = lenses()
  eq(
    { "2 backlinks", "2 words", "1 backlink" },
    vim.tbl_map(function(lens)
      return lens.command.title
    end, result)
  )
  eq("obsidian.show_section_references", result[1].command.command)
end

T["supports setext headings and ignores headings in code fences"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "Title\n=====\none two\n```\n# Not a heading\n```",
    ["source.md"] = "[[target#Title]]",
  })
  child.cmd("edit " .. files["target.md"])
  local result = lenses()
  eq(1, #result)
  eq("1 backlink", result[1].command.title)
  eq({ vim.uri_from_fname(files["target.md"]), 0, "#title" }, result[1].command.arguments)
end

T["section backlink command opens the matching reference"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "# Title\nbody",
    ["source.md"] = "[[target#Title]]",
  })
  child.cmd("edit " .. files["target.md"])
  local lens = lenses()[1]
  eq("1 backlink", lens.command.title)

  local opened = h.child_await(
    child,
    [[
    local api = require "obsidian.api"
    api.open_note = function(entry)
      done(entry.filename, entry.lnum)
    end
    require("obsidian.actions").show_section_references(vim.uri_from_bufnr(0), 0, "#title")
  ]],
    { desc = "open section backlink" }
  )
  eq(files["source.md"], opened)
end

return T
