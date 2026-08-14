local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function has_unlink(character)
  return h.child_await(
    child,
    ([=[
    local client = assert(vim.lsp.get_clients { name = "obsidian-ls" }[1])
    client.request("textDocument/codeAction", {
      textDocument = { uri = vim.uri_from_bufnr(0) },
      range = {
        start = { line = 0, character = %d },
        ["end"] = { line = 0, character = %d },
      },
      context = { diagnostics = {} },
    }, function(err, result)
      assert(not err, vim.inspect(err))
      for _, action in ipairs(result or {}) do
        if action.command and action.command.command == "obsidian.unlink" then
          done(true)
          return
        end
      end
      done(false)
    end, 0)
  ]=]):format(character, character)
  )
end

T["unlink is offered only when the requested position is on a link"] = function()
  local path = tostring(child.Obsidian.dir / "note.md")
  child.fn.writefile({ "[[target]] plain" }, path)
  child.cmd("edit " .. vim.fn.fnameescape(path))
  h.child_wait_for_lsp_client(child, "obsidian-ls")

  -- Keep the actual cursor off the link to ensure the request range is used.
  child.api.nvim_win_set_cursor(0, { 1, 12 })
  eq(true, has_unlink(2))
  eq(false, has_unlink(12))
end

return T
