local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

T["attaches the in-process server to base documents"] = function()
  local path = child.Obsidian.dir / "example.base"
  h.write("formulas:\n  bad: 10", path)

  child.cmd("edit " .. tostring(path))
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  h.child_wait(child, [[return #vim.diagnostic.get(0) == 2]], { desc = "Bases diagnostics" })

  eq("obsidian-base", child.bo.filetype)
  eq(true, child.b.obsidian_base)
  eq("base.missing-views", child.lua_get "vim.diagnostic.get(0)[1].code")
end

T["serves base code actions through LSP"] = function()
  local path = child.Obsidian.dir / "actions.base"
  h.write("formulas:\n  title: file.name", path)
  child.cmd("edit " .. tostring(path))
  h.child_wait_for_lsp_client(child, "obsidian-ls")

  local actions = h.child_lsp_request(
    child,
    "obsidian-ls",
    "textDocument/codeAction",
    [[{
      textDocument = { uri = vim.uri_from_bufnr(0) },
      range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
      context = { diagnostics = {} },
    }]],
    { desc = "Bases code actions" }
  )

  eq("Add a table view", actions[1].title)
end

return T
