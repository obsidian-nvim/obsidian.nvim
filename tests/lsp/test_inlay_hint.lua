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

local function link_hint(value, line, start_col, end_col)
  return link_hints(line, start_col, end_col)[value == "[[" and 1 or 2]
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
        for _, hint in ipairs(res) do
          for _, part in ipairs(type(hint.label) == "table" and hint.label or {}) do
            if part.command then
              part.command.arguments = nil
            end
          end
        end
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

T["resolves native hints before accepting them"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[vim.lsp.inlay_hint.enable(true, { bufnr = 0 })]]
  h.child_wait(child, [[return #vim.lsp.inlay_hint.get { bufnr = 0 } == 2]], { desc = "native inlay hints" })
  child.lua [[
    local client = vim.lsp.get_clients({ name = "obsidian-ls" })[1]
    client.server_capabilities.inlayHintProvider = { resolveProvider = true }
    require("obsidian.lsp.handlers")["inlayHint/resolve"] = function(hint, callback)
      _G.resolved_inlay_hint = true
      local resolved = vim.deepcopy(hint)
      resolved.label = "resolved"
      resolved.textEdits = { {
        range = {
          start = { line = 0, character = 2 },
          ["end"] = { line = 0, character = 6 },
        },
        newText = "resolved",
      } }
      callback(nil, resolved)
    end
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    _G.accepted_resolved_inlay_hint = require("obsidian.inlay_hints").accept()
  ]]

  eq(true, child.lua_get [[_G.accepted_resolved_inlay_hint]])
  eq(true, child.lua_get [[_G.resolved_inlay_hint]])
  eq("a resolved", child.lua_get [[vim.api.nvim_get_current_line()]])
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

T["does not suggest inside tags"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["project.md"] = "# project",
    ["tagged.md"] = "#project project",
  })
  setup_cache()

  child.cmd("edit " .. files["tagged.md"])

  eq(link_hints(0, 9, 16), run_inlay_hint())
end

T["formats relative suggestions from the source note directory"] = function()
  local source_dir = child.Obsidian.dir / "source"
  local other_dir = child.Obsidian.dir / "other"
  source_dir:mkdir()
  other_dir:mkdir()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["target.md"] = "# target",
    ["source/hints.md"] = "a target",
  })
  setup_cache()

  child.lua(([[
    Obsidian.opts.link.format = "relative"
    Obsidian.buf_dir = require("obsidian.path").new(%q)
  ]]):format(tostring(other_dir)))
  child.cmd("edit " .. files["source/hints.md"])
  child.lua(([[Obsidian.buf_dir = require("obsidian.path").new(%q)]]):format(tostring(other_dir)))

  eq(
    "[[../target|target]]",
    child.lua_get [[
      require("obsidian.api").current_note(0, { max_lines = vim.api.nvim_buf_line_count(0) })
        :link_suggestions()[1].candidates[1].new_text
    ]]
  )
end

T["does not suggest inside fenced code blocks"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["fenced.md"] = [=[before test
```lua
test
```
after test]=],
  })
  setup_cache()

  child.cmd("edit " .. files["fenced.md"])

  eq(vim.list_extend(link_hints(0, 7, 11), link_hints(4, 6, 10)), run_inlay_hint())
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

T["smart action executes the link suggestion command under cursor"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["hints.md"] = "a test",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[vim.lsp.inlay_hint.enable(true, { bufnr = 0 })]]
  h.child_wait(child, [[return #vim.lsp.inlay_hint.get { bufnr = 0 } == 2]], { desc = "native inlay hints" })
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    local action = require("obsidian.actions").smart_action()
    _G.link_suggestion_smart_action = action
    local keys = vim.api.nvim_replace_termcodes(action, true, false, true)
    vim.api.nvim_feedkeys(keys, "x", false)
  ]]

  eq("<cmd>lua require('obsidian.inlay_hints').accept()<cr>", child.lua_get [[_G.link_suggestion_smart_action]])
  h.child_wait(child, [=[return vim.api.nvim_get_current_line() == "a [[test]]"]=], { desc = "link suggestion action" })
end

T["smart action accepts a multi-word suggestion from its middle word"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["three word note.md"] = "# target",
    ["hints.md"] = "a three word note here",
  })
  setup_cache()

  child.cmd("edit " .. files["hints.md"])
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[vim.lsp.inlay_hint.enable(true, { bufnr = 0 })]]
  h.child_wait(child, [[return #vim.lsp.inlay_hint.get { bufnr = 0 } == 2]], { desc = "native inlay hints" })
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 9 })
    local action = require("obsidian.actions").smart_action()
    local keys = vim.api.nvim_replace_termcodes(action, true, false, true)
    vim.api.nvim_feedkeys(keys, "x", false)
  ]]

  h.child_wait(child, [=[return vim.api.nvim_get_current_line() == "a [[three word note]] here"]=], {
    desc = "multi-word link suggestion action",
  })
end

T["smart action ignores hints from other LSP clients"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["linked.md"] = "[[test]]",
  })
  child.cmd("edit " .. files["linked.md"])
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    local original_hint_get = vim.lsp.inlay_hint.get
    local original_client_get = vim.lsp.get_client_by_id
    vim.lsp.inlay_hint.get = function(filter)
      return { {
        bufnr = filter.bufnr,
        client_id = 99,
        inlay_hint = {
          position = { line = 0, character = 2 },
          label = { { value = "foreign", command = { title = "foreign", command = "foreign.command" } } },
        },
      } }
    end
    vim.lsp.get_client_by_id = function(id)
      return id == 99 and { name = "foreign-ls" } or nil
    end
    _G.smart_action_with_foreign_hint = require("obsidian.actions").smart_action()
    vim.lsp.inlay_hint.get = original_hint_get
    vim.lsp.get_client_by_id = original_client_get
  ]]

  eq("<cmd>Obsidian follow_link<cr>", child.lua_get [[_G.smart_action_with_foreign_hint]])
end

T["smart action falls back when inlay hint lookup is unavailable"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["linked.md"] = "[[test]]",
  })
  child.cmd("edit " .. files["linked.md"])
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 3 })
    local original_get = vim.lsp.inlay_hint.get
    vim.lsp.inlay_hint.get = nil
    _G.smart_action_without_hint_get = require("obsidian.actions").smart_action()
    _G.hints_without_hint_get = require("obsidian.inlay_hints").get()
    vim.lsp.inlay_hint.get = original_get
  ]]

  eq("<cmd>Obsidian follow_link<cr>", child.lua_get [[_G.smart_action_without_hint_get]])
  eq({}, child.lua_get [[_G.hints_without_hint_get]])
end

T["accepts a native hint when cursor is inside its declared range"] = function()
  child.lua [[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a three word note here" })
    vim.api.nvim_win_set_cursor(0, { 1, 9 })

    local original_get = vim.lsp.inlay_hint.get
    vim.lsp.inlay_hint.get = function(filter)
      _G.accept_hint_filter = filter
      local function item(command, position, range)
        return {
          bufnr = filter.bufnr,
          client_id = -1,
          inlay_hint = {
            position = { line = 0, character = position },
            label = { { value = command, command = { title = command, command = command } } },
            data = { range = range },
          },
        }
      end
      return {
        item("test.outside_hint", 0, {
          start = { line = 0, character = 0 },
          ["end"] = { line = 0, character = 1 },
        }),
        item("test.inside_hint", 2, {
          start = { line = 0, character = 2 },
          ["end"] = { line = 0, character = 17 },
        }),
      }
    end
    vim.lsp.commands["test.outside_hint"] = function()
      _G.accepted_hint = "outside"
    end
    vim.lsp.commands["test.inside_hint"] = function()
      _G.accepted_hint = "inside"
    end

    _G.accepted_hint_result = require("obsidian.inlay_hints").accept()
    vim.lsp.inlay_hint.get = original_get
  ]]

  eq(true, child.lua_get [[_G.accepted_hint_result]])
  eq("inside", child.lua_get [[_G.accepted_hint]])
  eq(true, child.lua_get [[_G.accept_hint_filter.range == nil]])
end

T["accepts a suffix hint without private range data"] = function()
  child.lua [[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "word" })
    vim.api.nvim_win_set_cursor(0, { 1, 2 })

    local original_get = vim.lsp.inlay_hint.get
    vim.lsp.inlay_hint.get = function(filter)
      return { {
        bufnr = filter.bufnr,
        client_id = -1,
        inlay_hint = {
          position = { line = 0, character = 4 },
          label = { {
            value = " suffix",
            command = { title = "suffix", command = "test.suffix_hint" },
          } },
        },
      } }
    end
    vim.lsp.commands["test.suffix_hint"] = function()
      _G.accepted_suffix_hint = true
    end

    _G.accepted_suffix_hint_result = require("obsidian.inlay_hints").accept()
    vim.lsp.inlay_hint.get = original_get
  ]]

  eq(true, child.lua_get [[_G.accepted_suffix_hint_result]])
  eq(true, child.lua_get [[_G.accepted_suffix_hint]])
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
    require("obsidian.picker").select = function(candidates, _, callback)
      _G.link_suggestion_options = vim.tbl_map(function(candidate)
        return candidate.new_text
      end, candidates)
      callback({ candidates[2] })
    end
    require("obsidian.actions").link_suggestion()
  ]]

  eq({ "[[one/test|test]]", "[[two/test|test]]" }, child.lua_get [[_G.link_suggestion_options]])
  eq("a [[two/test|test]]", child.lua_get [[vim.api.nvim_get_current_line()]])
end

T["does nothing when link suggestion selection is cancelled"] = function()
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
    require("obsidian.picker").select = function(_, _, callback)
      callback({})
    end
    require("obsidian.actions").link_suggestion()
  ]]

  eq("a test", child.lua_get [[vim.api.nvim_get_current_line()]])
end

T["uses a custom hints resolver with an LSP command"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["ipa.md"] = "  say /ˌɒnəmatəˈpiːə/ now",
  })
  setup_cache()

  child.lua [[
require("obsidian.actions").speak_ipa = function(ipa)
  _G.spoken_ipa = ipa
end
Obsidian.opts.resolvers.hints = function(ctx, done)
  local line = ctx.note.contents[1]
  local leading, ipa = line:match("(%s+)/([^/]+)/")
  local start_col = #leading
  local end_col = #leading + #ipa + 2
  done({ {
    position = { line = 0, character = end_col },
    label = { {
      value = " ▶",
      command = {
        title = "Speak IPA",
        command = "obsidian.speak_ipa",
        arguments = { ipa },
      },
    } },
    data = {
      range = {
        start = { line = 0, character = start_col },
        ["end"] = { line = 0, character = end_col },
      },
    },
  } })
end
  ]]

  child.cmd("edit " .. files["ipa.md"])
  local hints = run_inlay_hint()

  eq(1, #hints)
  eq({ line = 0, character = 23 }, hints[1].position)
  eq(" ▶", hints[1].label[1].value)
  eq("obsidian.speak_ipa", hints[1].label[1].command.command)

  h.child_wait_for_lsp_client(child, "obsidian-ls")
  child.lua [[vim.lsp.inlay_hint.enable(true, { bufnr = 0 })]]
  h.child_wait(child, [[return #vim.lsp.inlay_hint.get { bufnr = 0 } == 1]], { desc = "native custom inlay hint" })
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    require("obsidian.inlay_hints").accept()
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
    { link_hint("[[", 2, 0, 4) },
    run_inlay_hint {
      start = { line = 2, character = 0 },
      ["end"] = { line = 2, character = 4 },
    }
  )
end

T["honors character bounds in requested ranges"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["range.md"] = "a test test",
  })
  setup_cache()

  child.cmd("edit " .. files["range.md"])

  eq(
    { link_hint("]]", 0, 2, 6), link_hint("[[", 0, 7, 11) },
    run_inlay_hint {
      start = { line = 0, character = 3 },
      ["end"] = { line = 0, character = 8 },
    }
  )
  eq(
    {},
    run_inlay_hint {
      start = { line = 0, character = 0 },
      ["end"] = { line = 0, character = 0 },
    }
  )
end

T["loads and scans requested lines beyond the search limit"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "# test",
    ["long.md"] = string.rep("skip\n", 1001) .. "test",
  })
  setup_cache()

  child.cmd("edit " .. files["long.md"])
  child.lua [[
    local suggestions = require "obsidian.note.link_suggestion"
    local original_find_in_line = suggestions.find_in_line
    _G.scanned_link_suggestion_lines = 0
    suggestions.find_in_line = function(...)
      _G.scanned_link_suggestion_lines = _G.scanned_link_suggestion_lines + 1
      return original_find_in_line(...)
    end
  ]]

  eq(
    link_hints(1001, 0, 4),
    run_inlay_hint {
      start = { line = 1001, character = 0 },
      ["end"] = { line = 1001, character = 5 },
    }
  )
  eq(1, child.lua_get [[_G.scanned_link_suggestion_lines]])
end

return T
