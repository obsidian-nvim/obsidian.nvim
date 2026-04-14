local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

-- TODO: better test helpers
T["refs"] = MiniTest.new_set()

T["refs"]["can_complete should handle wiki links with text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "simple text [[foo"
  local request = {
    cursor_before_line = before,
    cursor_after_line = "",
    character = string.len(before),
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(12, insert_start)
  eq(17, insert_end)
end

T["refs"]["can_complete should handle wiki links with preceding Unicode text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "Unicode text ű [[foo"
  local request = {
    cursor_before_line = before,
    cursor_after_line = "",
    character = string.len(before),
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(16, insert_start)
  eq(21, insert_end)
end

T["completion"] = MiniTest.new_set()

T["completion"]["returns items for wiki link trigger"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[ta",
    ["target.md"] = [==[
---
id: target
aliases: []
tags: []
---
Target note content
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  child.lua [[
    local handler = require "obsidian.lsp.handlers.completion"
    handler({
      textDocument = { uri = vim.uri_from_bufnr(0) },
      position = { line = 0, character = 4 },
    }, function(err, res)
      _G._test_result = res
    end)
  ]]
  vim.uv.sleep(100)

  local result = child.lua_get [[_G._test_result]]
  eq("table", type(result))
  eq(true, result.isIncomplete)

  -- Should find "target" note.
  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.label and item.label:find "target" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["completion"]["returns items for tag trigger"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "#ta",
    ["tagged.md"] = [==[
---
id: tagged
aliases: []
tags:
  - task
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 3 })

  child.lua [[
    local handler = require "obsidian.lsp.handlers.completion"
    handler({
      textDocument = { uri = vim.uri_from_bufnr(0) },
      position = { line = 0, character = 3 },
    }, function(err, res)
      _G._test_result = res
    end)
  ]]
  vim.uv.sleep(100)

  local result = child.lua_get [[_G._test_result]]
  eq("table", type(result))
end

T["completion"]["isIncomplete is true"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[fo",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  child.lua [[
    local handler = require "obsidian.lsp.handlers.completion"
    handler({
      textDocument = { uri = vim.uri_from_bufnr(0) },
      position = { line = 0, character = 4 },
    }, function(err, res)
      _G._test_result = res
    end)
  ]]
  vim.uv.sleep(100)

  local is_incomplete = child.lua_get [[_G._test_result and _G._test_result.isIncomplete]]
  eq(true, is_incomplete)
end

return T
