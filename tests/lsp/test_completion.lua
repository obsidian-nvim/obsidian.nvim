local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function run_completion(line, character)
  return h.child_await(
    child,
    string.format(
      [[
        local handler = require "obsidian.lsp.handlers.completion"
        handler({
          textDocument = { uri = vim.uri_from_bufnr(0) },
          position = { line = %d, character = %d },
        }, function(_, res)
          done(res)
        end)
      ]],
      line,
      character
    ),
    { desc = "completion response", timeout = 2000 }
  )
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

T["tags"] = MiniTest.new_set()

T["tags"]["find_tags_start should accept in-progress prefixes"] = function()
  local completion = require "obsidian.completion.tags"

  eq("202", completion.find_tags_start "#202")
  eq("abc", completion.find_tags_start "#abc")
  eq("foo", completion.find_tags_start "(#foo")
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

  local result = run_completion(0, 4)
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

T["completion"]["returns unresolved wiki link targets"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[unre",
    ["source.md"] = "[[unresolved]]",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 6 })

  local result = run_completion(0, 6)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "[[unresolved]]" then
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

  local result = run_completion(0, 3)
  eq("table", type(result))
end

T["completion"]["isIncomplete is true"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[fo",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  local result = run_completion(0, 4)
  local is_incomplete = result and result.isIncomplete
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

  local result = run_completion(2, 6)
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

T["completion"]["returns items for unicode tag trigger in body"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "#snö",
    ["tagged.md"] = [==[
---
id: tagged
tags:
  - snöw
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 5 })

  local result = run_completion(0, 5)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "#snöw" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["completion"]["completes unicode tag inside frontmatter tags: list"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "---\ntags:\n  - caf\n---\n",
    ["tagged.md"] = [==[
---
id: tagged
tags:
  - café
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 3, 7 })

  local result = run_completion(2, 7)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "café" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["completion"]["returns items for CJK tag trigger in body"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "#中",
    ["tagged.md"] = [==[
---
id: tagged
tags:
  - 中文
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  -- byte len of "#中" = 1 + 3
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  local result = run_completion(0, 4)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "#中文" then
      found = true
      break
    end
  end
  eq(true, found)
end

T["completion"]["completes CJK tag inside frontmatter tags: list"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "---\ntags:\n  - 中\n---\n",
    ["tagged.md"] = [==[
---
id: tagged
tags:
  - 中文
---
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  -- byte len of "  - 中" = 4 + 3 = 7
  child.api.nvim_win_set_cursor(0, { 3, 7 })

  local result = run_completion(2, 7)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.textEdit and item.textEdit.newText == "中文" then
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

  local result = h.child_await(
    child,
    [[
      local handler = require "obsidian.lsp.handlers.completion"
      handler({
        textDocument = { uri = vim.uri_from_bufnr(0) },
        position = { line = 0, character = 14 },
      }, function(_, res)
        vim.schedule(function()
          local ok, result = pcall(function()
            local note_path
            local has_create = false
            for _, item in ipairs((res or {}).items or {}) do
              if item.command and item.command.command == "obsidian.write_note" then
                has_create = true
                local note = item.command.arguments[1]
                require("obsidian.actions").write_note(note)
                note_path = tostring(note.path)
                break
              end
            end
            return { has_create = has_create, note_path = note_path }
          end)
          if ok then
            done(result)
          else
            done({ error = result })
          end
        end)
      end)
    ]],
    { desc = "completion create command" }
  )
  if result.error then
    error(result.error)
  end
  eq(true, result.has_create)
  local note_path = result.note_path
  eq("string", type(note_path))
  eq(1, vim.fn.filereadable(note_path))
end

return T
