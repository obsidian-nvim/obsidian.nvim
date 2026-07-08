local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function run_inlay_hint(range)
  local range_lua = range and vim.inspect(range) or "nil"
  return h.child_await(
    child,
    ([[
      local handler = require "obsidian.lsp.handlers.inlay_hint"
      handler({
        textDocument = { uri = vim.uri_from_bufnr(0) },
        range = %s,
      }, function(_, res)
        done(res)
      end)
    ]]):format(range_lua),
    { desc = "inlayHint response", timeout = 2000 }
  )
end

T["suggests wiki brackets around test words"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["hints.md"] = "a test and contest and test.",
  })

  child.cmd("edit " .. files["hints.md"])

  eq({
    {
      position = { line = 0, character = 2 },
      label = "[[",
      paddingLeft = false,
      paddingRight = false,
    },
    {
      position = { line = 0, character = 6 },
      label = "]]",
      paddingLeft = false,
      paddingRight = false,
    },
    {
      position = { line = 0, character = 23 },
      label = "[[",
      paddingLeft = false,
      paddingRight = false,
    },
    {
      position = { line = 0, character = 27 },
      label = "]]",
      paddingLeft = false,
      paddingRight = false,
    },
  }, run_inlay_hint())
end

T["does not suggest inside existing wiki links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["linked.md"] = "[[test]] test [[also test here]]",
  })

  child.cmd("edit " .. files["linked.md"])

  eq({
    {
      position = { line = 0, character = 9 },
      label = "[[",
      paddingLeft = false,
      paddingRight = false,
    },
    {
      position = { line = 0, character = 13 },
      label = "]]",
      paddingLeft = false,
      paddingRight = false,
    },
  }, run_inlay_hint())
end

T["suggests hash for existing tags"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["tags.md"] = "#book",
    ["suggest.md"] = "book #book notebook [[book]] bookish",
  })

  child.cmd("edit " .. files["suggest.md"])

  eq({
    {
      position = { line = 0, character = 0 },
      label = "#",
      paddingLeft = false,
      paddingRight = false,
    },
  }, run_inlay_hint())
end

T["didChange requests inlay hint refresh"] = function()
  child.lua [[
    local handler = require "obsidian.lsp.handlers.did_change"
    handler({}, {
      server_request = function(method, params)
        _G.inlay_hint_refresh_method = method
        _G.inlay_hint_refresh_params_is_nil = params == nil
      end,
    })
  ]]

  h.child_wait(child, "return _G.inlay_hint_refresh_method ~= nil", { desc = "inlay hint refresh" })
  eq("workspace/inlayHint/refresh", child.lua_get "inlay_hint_refresh_method")
  eq(true, child.lua_get "inlay_hint_refresh_params_is_nil")
end

T["respects requested range"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["range.md"] = [[test
skip
test]],
  })

  child.cmd("edit " .. files["range.md"])

  eq(
    {
      {
        position = { line = 2, character = 0 },
        label = "[[",
        paddingLeft = false,
        paddingRight = false,
      },
      {
        position = { line = 2, character = 4 },
        label = "]]",
        paddingLeft = false,
        paddingRight = false,
      },
    },
    run_inlay_hint {
      start = { line = 2, character = 0 },
      ["end"] = { line = 2, character = 4 },
    }
  )
end

return T
