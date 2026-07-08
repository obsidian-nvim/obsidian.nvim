local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_cache()
  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
end

local function link_hints(line, start_col, end_col, new_text)
  local edit = {
    range = {
      start = { line = line, character = start_col },
      ["end"] = { line = line, character = end_col },
    },
    newText = new_text,
  }
  return {
    {
      position = { line = line, character = start_col },
      label = "[[",
      paddingLeft = false,
      paddingRight = false,
      textEdits = { edit },
    },
    {
      position = { line = line, character = end_col },
      label = "]]",
      paddingLeft = false,
      paddingRight = false,
      textEdits = { edit },
    },
  }
end

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

T["suggests wiki brackets for link suggestions"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test and contest and test.",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])

  eq(vim.list_extend(link_hints(0, 2, 6, "[[test]]"), link_hints(0, 23, 27, "[[test]]")), run_inlay_hint())
end

T["publishes link suggestions to native inlay hint interface"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[vim.lsp.inlay_hint.enable(true, { bufnr = 0 })]]
  h.child_wait(child, [[return #vim.lsp.inlay_hint.get { bufnr = 0 } == 2]], { desc = "native inlay hints" })

  eq(
    { "[[", "]]" },
    child.lua_get [[vim.tbl_map(function(item) return item.inlay_hint.label end, vim.lsp.inlay_hint.get { bufnr = 0 })]]
  )
end

T["does not suggest inside existing wiki links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["linked.md"] = "[[test]] test [[also test here]]",
  })
  setup_cache()

  child.cmd("edit " .. files["linked.md"])

  eq(link_hints(0, 9, 13, "[[test]]"), run_inlay_hint())
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
    ["test.md"] = "# test",
    ["range.md"] = [[test
skip
test]],
  })
  setup_cache()

  child.cmd("edit " .. files["range.md"])

  eq(
    link_hints(2, 0, 4, "[[test]]"),
    run_inlay_hint {
      start = { line = 2, character = 0 },
      ["end"] = { line = 2, character = 4 },
    }
  )
end

return T
