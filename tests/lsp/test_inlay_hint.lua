local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_cache()
  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
end

local function link_hints(line, start_col, end_col)
  local range = {
    start = { line = line, character = start_col },
    ["end"] = { line = line, character = end_col },
  }
  local function hint(value, character)
    return {
      position = { line = line, character = character },
      label = {
        {
          value = value,
          command = {
            title = "Apply link suggestion",
            command = "obsidian.link_suggestion",
          },
        },
      },
      paddingLeft = false,
      paddingRight = false,
      data = { range = range },
    }
  end
  return {
    hint("[[", start_col),
    hint("]]", end_col),
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

  eq(vim.list_extend(link_hints(0, 2, 6), link_hints(0, 23, 27)), run_inlay_hint())
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
    child.lua_get [[vim.tbl_map(function(item) return item.inlay_hint.label[1].value end, vim.lsp.inlay_hint.get { bufnr = 0 })]]
  )
end

T["does not suggest inside existing wiki links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["linked.md"] = "[[test]] test [[also test here]]",
  })
  setup_cache()

  child.cmd("edit " .. files["linked.md"])

  eq(link_hints(0, 9, 13), run_inlay_hint())
end

-- TODO: once cache is auto per vault
-- T["uses the workspace that owns the buffer for link suggestions"] = function()
--   h.mock_vault_contents(child.Obsidian.dir, {
--     ["local.md"] = "# wrong workspace",
--   })
--   setup_cache()
--
--   local ws2 = child.lua [[
--     local Path = require "obsidian.path"
--     local Workspace = require "obsidian.workspace"
--     local dir = Path.temp { suffix = "-obsidian-ws2" }
--     dir:mkdir { parents = true }
--     table.insert(Obsidian.workspaces, Workspace.new { path = tostring(dir), name = "ws2" })
--     vim.fn.mkdir(tostring(dir / "folder"), "p")
--     vim.fn.writefile({ "# local" }, tostring(dir / "folder" / "local.md"))
--     vim.fn.writefile({ "a local" }, tostring(dir / "hints.md"))
--     return { dir = tostring(dir), hints = tostring(dir / "hints.md") }
--   ]]
--
--   child.cmd("edit " .. ws2.hints)
--
--   eq(link_hints(0, 2, 7, "[[folder/local|local]]"), run_inlay_hint())
--   child.lua(([[vim.fn.delete(%q, "rf")]]):format(ws2.dir))
-- end

T["skips stale link suggestions after target rename"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  child.lua [[
    vim.uv.fs_rename(tostring(Obsidian.dir / "test.md"), tostring(Obsidian.dir / "renamed.md"))
  ]]

  eq({}, run_inlay_hint())
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

T["smart action executes the link suggestion command under cursor"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  run_inlay_hint()
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    local action = require("obsidian.actions").smart_action()
    _G.link_suggestion_smart_action = action
    local keys = vim.api.nvim_replace_termcodes(action, true, false, true)
    vim.api.nvim_feedkeys(keys, "x", false)
  ]]

  eq(
    "<cmd>lua require('obsidian.inlay_hints').accept_under_cursor()<cr>",
    child.lua_get [[_G.link_suggestion_smart_action]]
  )
  h.child_wait(child, [=[return vim.api.nvim_get_current_line() == "a [[test]]"]=], { desc = "link suggestion action" })
end

T["selects between multiple link suggestion candidates"] = function()
  local one_dir = child.Obsidian.dir / "one"
  local two_dir = child.Obsidian.dir / "two"
  one_dir:mkdir()
  two_dir:mkdir()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["one/test.md"] = "# one",
    ["two/test.md"] = "# two",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    Obsidian.picker.pick = function(options, opts)
      _G.link_suggestion_options = vim.tbl_map(function(option)
        return option.text
      end, options)
      opts.callback(options[2])
    end
    require("obsidian.actions").link_suggestion()
  ]]

  eq({ "[[one/test|test]]", "[[two/test|test]]" }, child.lua_get [[_G.link_suggestion_options]])
  eq("a [[two/test|test]]", child.lua_get [[vim.api.nvim_get_current_line()]])
end

T["registers line scanners with command hints"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["ipa.md"] = "  say /ˌɒnəmatəˈpiːə/ now",
  })
  setup_cache()

  child.lua [[

local Range = require("obsidian.range")
require("obsidian").inlay_hints.register({
   name = "ipa-test",
   scan = function(ctx)
      local leading, ipa = ctx.line:match("(%s+)/([^/]+)/")
      if not ipa then
         return
      end

      local start_col = #leading + 1
      local end_col = #leading + #ipa + 2
      local range = Range.new(ctx.row, start_col - 1, ctx.row, end_col)
      ctx.add({
         range = range,
         position = { line = ctx.row, character = end_col },
         label = " ▶",
         command = function()
            _G.spoken_ipa = ipa
         end,
      })
   end,
})
  ]]

  child.cmd("edit " .. files["ipa.md"])
  local hints = run_inlay_hint()

  eq(1, #hints)
  eq({ line = 0, character = 23 }, hints[1].position)
  eq(" ▶", hints[1].label[1].value)
  eq("obsidian.inlay_hint_command", hints[1].label[1].command.command)

  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    require("obsidian.inlay_hints").accept_under_cursor()
  ]]
  eq("ˌɒnəmatəˈpiːə", child.lua_get [[_G.spoken_ipa]])
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
    link_hints(2, 0, 4),
    run_inlay_hint {
      start = { line = 2, character = 0 },
      ["end"] = { line = 2, character = 4 },
    }
  )
end

return T
