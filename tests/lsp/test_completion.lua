local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function run_completion(line, character)
  child.lua(string.format(
    [[
    _G._test_result = nil
    local done = false
    local handler = require "obsidian.lsp.handlers.completion"
    handler({
      textDocument = { uri = vim.uri_from_bufnr(0) },
      position = { line = %d, character = %d },
    }, function(_, res)
      _G._test_result = res
      done = true
    end)
    vim.wait(2000, function() return done end, 10)
  ]],
    line,
    character
  ))
end

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

  run_completion(0, 4)

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

  run_completion(0, 3)

  local result = child.lua_get [[_G._test_result]]
  eq("table", type(result))
end

T["completion"]["isIncomplete is true"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[fo",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  run_completion(0, 4)

  local is_incomplete = child.lua_get [[_G._test_result and _G._test_result.isIncomplete]]
  eq(true, is_incomplete)
end

T["completion"]["completes tag inside frontmatter tags: list"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "---\ntags:\n  - ta\n---\n",
    ["tagged.md"] = [==[
---
id: tagged
tags:
  - task
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  -- Line 3 (1-indexed) "  - ta", cursor after "ta" at byte 6.
  child.api.nvim_win_set_cursor(0, { 3, 6 })

  run_completion(2, 6)

  local result = child.lua_get [[_G._test_result]]
  eq("table", type(result))

  -- Frontmatter form: newText is bare tag (no '#').
  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "task" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["completion"]["create_new emits write_note command that writes file"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[brandnewnote",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 14 })

  run_completion(0, 14)

  child.lua [[
    _G._note_path = nil
    _G._has_create = false
    for _, item in ipairs((_G._test_result or {}).items or {}) do
      if item.command and item.command.command == "obsidian.write_note" then
        _G._has_create = true
        local note = item.command.arguments[1]
        require("obsidian.actions").write_note(note)
        _G._note_path = tostring(note.path)
        break
      end
    end
  ]]
  eq(true, child.lua_get [[_G._has_create]])
  local note_path = child.lua_get [[_G._note_path]]
  eq("string", type(note_path))
  eq(1, vim.fn.filereadable(note_path))
end

return T
