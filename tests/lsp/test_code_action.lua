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

T["only intentional command IDs are installed and advertised"] = function()
  local path = tostring(child.Obsidian.dir / "note.md")
  child.fn.writefile({ "[[target]]" }, path)
  child.cmd("edit " .. vim.fn.fnameescape(path))
  h.child_wait_for_lsp_client(child, "obsidian-ls")

  eq(
    {},
    child.lua [[
    local client = assert(vim.lsp.get_clients({ name = "obsidian-ls" })[1])
    local ids = client.server_capabilities.executeCommandProvider.commands
    local installed = vim.tbl_filter(function(id)
      return vim.startswith(id, "obsidian.")
    end, vim.tbl_keys(vim.lsp.commands))
    table.sort(installed)
    assert(vim.deep_equal(ids, installed))
    local missing = {}
    for _, id in ipairs({ "unlink", "write_note", "footnote_new", "block_reference_new", "link_suggestion" }) do
      if not vim.tbl_contains(ids, "obsidian." .. id) then
        missing[#missing + 1] = id
      end
    end
    return missing
  ]]
  )

  for _, id in ipairs { "obsidian._toggle_checkbox", "_toggle_checkbox", "unlink", "obsidian.new" } do
    eq(
      -32601,
      h.child_await(
        child,
        ([=[
      local client = assert(vim.lsp.get_clients({ name = "obsidian-ls" })[1])
      client:request("workspace/executeCommand", { command = %q }, function(err)
        done(err and err.code)
      end, 0)
    ]=]):format(id)
      )
    )
  end
end

T["server fallback executes a built-in code action in the requested buffer"] = function()
  local path = tostring(child.Obsidian.dir / "note.md")
  child.fn.writefile({ "[[target|label]]" }, path)
  child.cmd("edit " .. vim.fn.fnameescape(path))
  h.child_wait_for_lsp_client(child, "obsidian-ls")

  eq(
    { "label", "unrelated" },
    h.child_await(
      child,
      [[
    local source = vim.api.nvim_get_current_buf()
    local client = assert(vim.lsp.get_clients({ name = "obsidian-ls" })[1])
    client:request("textDocument/codeAction", {
      textDocument = { uri = vim.uri_from_bufnr(source) },
      range = { start = { line = 0, character = 2 }, ["end"] = { line = 0, character = 2 } },
      context = { diagnostics = {} },
    }, function(err, result)
      assert(not err, vim.inspect(err))
      for _, action in ipairs(result) do
        if action.command and action.command.command == "obsidian.unlink" then
          assert(action.data == nil, "internal code action data must not leak into the response")
          vim.cmd "enew"
          vim.api.nvim_set_current_line("unrelated")
          client:request("workspace/executeCommand", action.command, function(execute_err)
            assert(not execute_err, vim.inspect(execute_err))
            done({ vim.api.nvim_buf_get_lines(source, 0, 1, false)[1], vim.api.nvim_get_current_line() })
          end, source)
          return
        end
      end
      error "unlink action not offered"
    end, source)
  ]]
    )
  )
end

T["custom code action dispatch survives initialization and is removed with the action"] = function()
  eq(
    { "custom:one", "custom:two", -32601, true },
    h.child_await(
      child,
      [[
    local obsidian = require "obsidian"
    local id = "obsidian.unlink"
    local received = {}
    obsidian.code_action.add {
      name = "unlink",
      title = "Custom unlink",
      fn = function(value)
        received[#received + 1] = "custom:" .. value
      end,
    }

    local initialize = require "obsidian.lsp.handlers.initialize"
    local execute = require "obsidian.lsp.handlers.workspace_execute_command"
    local function init()
      initialize({}, function() end, { notification = function() end })
    end
    local client_handler = vim.lsp.commands[id]
    init()
    init()
    assert(client_handler == vim.lsp.commands[id], "initialization replaced the custom handler")
    client_handler { command = id, arguments = { "one" } }
    vim.schedule(function()
      execute({ command = id, arguments = { "two" } }, function(err)
        assert(not err, vim.inspect(err))
      end)
      obsidian.code_action.del "unlink"
      local restored = vim.lsp.commands[id] ~= nil and vim.lsp.commands[id] ~= client_handler
      obsidian.code_action.add { name = "custom_test", title = "Test", fn = function() end }
      obsidian.code_action.del "custom_test"
      assert(vim.lsp.commands["obsidian.custom_test"] == nil)
      execute({ command = "obsidian.custom_test" }, function(err)
        done({ received[1], received[2], err.code, restored })
      end)
    end)
  ]]
    )
  )
end

return T
