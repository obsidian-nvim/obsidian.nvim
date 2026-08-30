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

local function accept_completion(item)
  child.lua(([[
    local item = %s
    vim.lsp.util.apply_text_edits({ item.textEdit }, vim.api.nvim_get_current_buf(), "utf-8")
    if item.command then
      require("obsidian.actions").block_reference_new(unpack(item.command.arguments))
    end
  ]]):format(vim.inspect(item)))
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

T["refs"]["heading_search recognizes vault heading syntax"] = function()
  local completion = require "obsidian.completion.refs"

  eq("HTTP", completion.heading_search "## HTTP")
  eq("", completion.heading_search "##")
  eq(nil, completion.heading_search "target#HTTP")
end

T["tags"] = MiniTest.new_set()

T["tags"]["find_tags_start should accept in-progress prefixes"] = function()
  local completion = require "obsidian.completion.tags"

  eq("202", completion.find_tags_start "#202")
  eq("abc", completion.find_tags_start "#abc")
  eq("foo", completion.find_tags_start "(#foo")
end

T["footnotes"] = MiniTest.new_set()

T["footnotes"]["can_complete should handle footnote triggers"] = function()
  local completion = require "obsidian.completion.footnotes"

  local before = "some claim[^fo"
  local request = {
    cursor_before_line = before,
    cursor_after_line = "",
    character = string.len(before),
  }

  local can_complete, term, insert_start, insert_end = completion.can_complete(request)
  eq(true, can_complete)
  eq("fo", term)
  eq(10, insert_start)
  eq(14, insert_end)
end

T["footnotes"]["can_complete should consume a trailing closing bracket"] = function()
  local completion = require "obsidian.completion.footnotes"

  local before = "some claim[^fo"
  local request = {
    cursor_before_line = before,
    cursor_after_line = "]",
    character = string.len(before),
  }

  local can_complete, term, insert_start, insert_end = completion.can_complete(request)
  eq(true, can_complete)
  eq("fo", term)
  eq(10, insert_start)
  eq(15, insert_end)
end

T["footnotes"]["can_complete should not trigger on wiki block links"] = function()
  local completion = require "obsidian.completion.footnotes"

  local before = "[[^block"
  local request = {
    cursor_before_line = before,
    cursor_after_line = "",
    character = string.len(before),
  }

  eq(false, completion.can_complete(request))
end

T["completion"] = MiniTest.new_set()

T["completion"]["triggers on [^ with new footnote first, then numeric order"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "claim[^\n\n[^10]: tenth\n[^1]: https://neovim.io\n[^2]: second",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  eq("table", type(result))

  ---@type lsp.CompletionItem[]
  local fn_items = vim.tbl_filter(function(item)
    return item.filterText and vim.startswith(item.filterText, "[^")
  end, result.items or {})
  table.sort(fn_items, function(a, b)
    return a.sortText < b.sortText
  end)

  -- New footnote with the next free numeric id comes first.
  eq("[^11]: New footnote", fn_items[1].label)
  eq("[^11]", fn_items[1].textEdit.newText)
  eq("11", fn_items[1].command.arguments[1])
  eq(nil, fn_items[1].documentation)
  eq(child.api.nvim_get_current_buf(), fn_items[1].command.arguments[2])
  eq({ 1, 9 }, fn_items[1].command.arguments[3])

  -- Then existing footnotes in numeric order.
  eq("[^1]: https://neovim.io", fn_items[2].label)
  eq(nil, fn_items[2].documentation)
  eq(5, fn_items[2].textEdit.range.start.character)
  eq("[^2]: second", fn_items[3].label)
  eq("[^10]: tenth", fn_items[4].label)
end

T["completion"]["truncates long footnote labels"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "claim[^\n\n[^1]: " .. string.rep("x", 100),
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.filterText == "[^1]"
  end)
  assert(item, "no existing footnote item found")
  eq(80, vim.fn.strchars(item.label))
  eq(true, vim.endswith(item.label, "…"))
  eq(nil, item.documentation)
end

T["completion"]["suggests [^2] when [^1] exists"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "claim[^\n\n[^1]: https://neovim.io",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  eq("table", type(result))

  local found = false
  for _, item in ipairs(result.items or {}) do
    if item.label == "[^2]: New footnote" then
      found = true
      eq("0", item.sortText)
      eq("2", item.command.arguments[1])
      break
    end
  end
  eq(true, found)
end

T["completion"]["offers create item for unresolved footnote"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "claim[^new",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  eq("table", type(result))

  ---@type lsp.CompletionItem|?
  local create_item
  for _, item in ipairs(result.items or {}) do
    if item.label == "[^new] (create)" then
      create_item = item
      break
    end
  end
  assert(create_item, "no create item found")
  eq("obsidian.footnote_new", create_item.command.command)
  eq("[^new]", create_item.textEdit.newText)
  eq("new", create_item.command.arguments[1])
  eq(child.api.nvim_get_current_buf(), create_item.command.arguments[2])
  eq({ 1, 10 }, create_item.command.arguments[3])
  eq(nil, create_item.documentation)

  -- Executing the action should prompt for content, insert the definition, and restore the accepted ref cursor.
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "claim[^new]" })
  child.api.nvim_win_set_cursor(0, { 1, 7 })
  child.lua [[
    vim.fn.input = function()
      return "the new footnote"
    end
    require("obsidian.actions").footnote_new("new", vim.api.nvim_get_current_buf(), { 1, 10 })
  ]]
  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("[^new]: the new footnote", lines[#lines])
  eq({ 1, 11 }, child.api.nvim_win_get_cursor(0))
end

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

T["completion"]["searches vault headings without cache"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##api",
    ["target.md"] = "# HTTP API Guide",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "HTTP API Guide — target"
  end)
  assert(item, "no vault heading completion found")
  eq("[[target#HTTP API Guide]]", item.textEdit.newText)
end

T["completion"]["searches normalized heading anchors without cache"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##http-api",
    ["target.md"] = "# HTTP API Guide",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 12 })

  local result = run_completion(0, 12)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "HTTP API Guide — target"
  end)
  assert(item, "no normalized heading completion found")
end

T["completion"]["heading search takes precedence over block syntax"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##x^2",
    ["target.md"] = "# x^2 Formula",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "x^2 Formula — target"
  end)
  assert(item, "caret heading query was not completed")
end

T["completion"]["uses parseable anchors for headings with wiki delimiters"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##input",
    ["target.md"] = "# Input | Output",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 9 })

  local result = run_completion(0, 9)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "Input | Output — target"
  end)
  assert(item, "no delimiter heading completion found")
  eq("[[target#input--output]]", item.textEdit.newText)
end

T["completion"]["disambiguates duplicate note basenames"] = function()
  child.fn.mkdir(tostring(child.Obsidian.dir / "one"), "p")
  child.fn.mkdir(tostring(child.Obsidian.dir / "two"), "p")
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##shared",
    ["one/target.md"] = "# Shared One",
    ["two/target.md"] = "# Shared Two",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local links = {}
  for _, item in ipairs(result.items or {}) do
    if item.label == "Shared One — target" or item.label == "Shared Two — target" then
      links[#links + 1] = item.textEdit.newText
    end
  end
  table.sort(links)
  eq({
    "[[one/target#Shared One|target ❯ Shared One]]",
    "[[two/target#Shared Two|target ❯ Shared Two]]",
  }, links)
end

T["completion"]["lists vault headings with an empty query"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##",
    ["target.md"] = "# Any Heading",
  })

  child.lua [[require("obsidian.cache").shutdown()]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })

  local result = run_completion(0, 4)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "Any Heading — target"
  end)
  assert(item, "no heading completion found for empty query")
end

T["completion"]["searches cached vault headings without filesystem search"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##cache",
    ["target.md"] = "# Cache Heading",
  })

  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
  child.lua [[
    local search = require "obsidian.search"
    _G.original_find_notes_async = search.find_notes_async
    search.find_notes_async = function()
      error "filesystem heading search should not run"
    end
  ]]

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 9 })
  local result = run_completion(0, 9)

  child.lua [[
    require("obsidian.search").find_notes_async = _G.original_find_notes_async
    _G.original_find_notes_async = nil
    require("obsidian.cache").shutdown()
  ]]

  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "Cache Heading — target"
  end)
  assert(item, "no cached vault heading completion found")
  eq("[[target#Cache Heading]]", item.textEdit.newText)
end

T["completion"]["cached heading search uses unsaved loaded buffers"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##unsaved",
    ["target.md"] = "# Old Heading",
  })

  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })
  child.cmd("edit " .. tostring(child.Obsidian.dir / "target.md"))
  child.api.nvim_buf_set_lines(0, 0, 1, false, { "# Unsaved Heading" })
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 11 })

  local result = run_completion(0, 11)
  child.lua [[require("obsidian.cache").shutdown()]]

  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "Unsaved Heading — target"
  end)
  assert(item, "no unsaved loaded heading completion found")
  eq("[[target#Unsaved Heading]]", item.textEdit.newText)
end

T["completion"]["vault heading completion honors markdown link style"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[##api",
    ["target.md"] = "# HTTP API Guide",
  })

  child.lua [[
    require("obsidian.cache").shutdown()
    Obsidian.opts.link.style = "markdown"
  ]]
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  child.lua [[Obsidian.opts.link.style = "wiki"]]
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "HTTP API Guide — target"
  end)
  assert(item, "no markdown vault heading completion found")
  eq("[target ❯ HTTP API Guide](target.md#http-api-guide)", item.textEdit.newText)
end

T["completion"]["creates a vault-wide block reference from unlabeled content"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^needle",
    ["target.md"] = "A needle paragraph",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.command.command == "obsidian.block_reference_new"
  end)
  assert(item, "no unlabeled block completion found")
  assert(not vim.iter(result.items or {}):any(function(candidate)
    return candidate.command and candidate.command.command == "obsidian.write_note"
  end), "block search offered to create a note")

  accept_completion(item)

  local target_line = vim.iter(vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))):find(function(line)
    return vim.startswith(line, "A needle paragraph")
  end)
  assert(target_line, "target paragraph disappeared")
  local block_id = target_line:match "(%^[0-9a-f]+)$"
  assert(block_id, "target paragraph has no generated block ID")
  eq("A needle paragraph " .. block_id, target_line)
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["creates a block embed while preserving the leading bang"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "![[^^embed needle",
    ["target.md"] = "An embed needle paragraph",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 17 })

  local result = run_completion(0, 17)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "An embed needle paragraph — target"
  end)
  assert(item, "no generated block embed completion found")
  accept_completion(item)

  local target_line = vim.iter(vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))):find(function(line)
    return vim.startswith(line, "An embed needle paragraph")
  end)
  assert(target_line, "embedded target paragraph disappeared")
  local block_id = target_line:match "(%^[0-9a-f]+)$"
  assert(block_id, "embedded target has no generated block ID")
  eq("![[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["creates a named-note block reference from unlabeled content after hash caret"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[target#^needle",
    ["target.md"] = "A named needle paragraph",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 16 })

  local result = run_completion(0, 16)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "A named needle paragraph"
  end)
  assert(item, "no named-note unlabeled block completion found")
  assert(
    vim.iter(vim.lsp.completion._lsp_to_complete_items(result, "[[target#^needle")):any(function(candidate)
      return candidate.abbr == item.label
    end),
    "Neovim filtered out the named-note block completion"
  )
  accept_completion(item)

  local target_line = vim.iter(vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))):find(function(line)
    return vim.startswith(line, "A named needle paragraph")
  end)
  assert(target_line, "named-note target paragraph disappeared")
  local block_id = target_line:match "(%^[0-9a-f]+)$"
  assert(block_id, "named-note target has no generated block ID")
  eq("A named needle paragraph " .. block_id, target_line)
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["creates a named-note block reference from unlabeled content after bare caret"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[target^named needle",
    ["target.md"] = "A second named needle paragraph",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 21 })

  local result = run_completion(0, 21)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "A second named needle paragraph"
  end)
  assert(item, "no bare-caret named-note block completion found")
  assert(
    vim.iter(vim.lsp.completion._lsp_to_complete_items(result, "[[target^named needle")):any(function(candidate)
      return candidate.abbr == item.label
    end),
    "Neovim filtered out the bare-caret named-note block completion"
  )
  accept_completion(item)

  local target_line = vim.iter(vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))):find(function(line)
    return vim.startswith(line, "A second named needle paragraph")
  end)
  assert(target_line, "bare-caret named-note target paragraph disappeared")
  local block_id = target_line:match "(%^[0-9a-f]+)$"
  assert(block_id, "bare-caret named-note target has no generated block ID")
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["searches and displays existing block IDs"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^quote-of-the-day",
    ["target.md"] = "Unrelated content ^quote-of-the-day",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 20 })

  local result = run_completion(0, 20)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "Unrelated content ^quote-of-the-day — target"
  end)
  assert(item, "existing block ID was not searchable and visible")
  eq(nil, item.command)
  eq("[[target#^quote-of-the-day]]", item.textEdit.newText)
end

T["completion"]["creates a current-note block reference from a bare caret trigger"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "A local paragraph\n\n[[^",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 3, 3 })

  local result = run_completion(2, 3)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.command.command == "obsidian.block_reference_new"
  end)
  assert(item, "no current-note block completion found")
  accept_completion(item)

  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local block_id = lines[1]:match "(%^[0-9a-f]+)$"
  assert(block_id, "local paragraph has no generated block ID")
  eq("A local paragraph " .. block_id, lines[1])
  eq("[[#" .. block_id .. "]]", lines[3])
end

T["completion"]["adds a block ID to the selected list item"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^first item",
    ["target.md"] = "- first item\n- second item",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 14 })

  local result = run_completion(0, 14)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "- first item — target"
  end)
  assert(item, "no first-list-item completion found")
  accept_completion(item)

  local lines = vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))
  local first_item = vim.iter(lines):find(function(line)
    return vim.startswith(line, "- first item")
  end)
  assert(first_item and first_item:match " %^[0-9a-f]+$", "selected list item has no block ID")
  eq("- second item", lines[#lines])
end

T["completion"]["adds a multiline list-item ID on an indented line"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^Paperclip",
    ["target.md"] = "- Gemmy\n    $$Paperclip / Pen$$\n- Unhelpful assistant",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 13 })

  local result = run_completion(0, 13)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "- Gemmy $$Paperclip / Pen$$ — target"
  end)
  assert(item, "no multiline list-item completion found")
  eq("- Gemmy $$Paperclip / Pen$$ — target", item.label)
  accept_completion(item)

  local lines = vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))
  local content_line = vim.iter(lines):enumerate():find(function(_, line)
    return line == "    $$Paperclip / Pen$$"
  end)
  assert(content_line, "list-item continuation disappeared")
  local block_id = lines[content_line + 1]:match "^    (%^[0-9a-f]+)$"
  assert(block_id, "multiline list-item ID is not on an indented line")
  eq("- Unhelpful assistant", lines[content_line + 2])
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["creates a reference to a whole list"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^Alpha whole",
    ["target.md"] = "- Alpha whole\n- Beta whole",
  })

  child.cmd "set hidden"
  child.cmd("edit " .. tostring(child.Obsidian.dir / "target.md"))
  local target_bufnr = child.api.nvim_get_current_buf()
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 15 })

  local result = run_completion(0, 15)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "- Alpha whole - Beta whole — target"
  end)
  assert(item, "no whole-list completion found")
  accept_completion(item)

  local lines = child.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
  local block_id = lines[4] and lines[4]:match "^%^[0-9a-f]+$"
  assert(block_id, "whole-list ID is not surrounded by blank lines")
  eq({ "- Alpha whole", "- Beta whole", "", block_id, "" }, lines)
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["reuses a whole-list block ID"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^Alpha manual",
    ["target.md"] = "- Alpha manual\n- Beta manual\n\n^whole-list",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 16 })

  local result = run_completion(0, 16)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "- Alpha manual - Beta manual ^whole-list — target"
  end)
  assert(item, "no existing whole-list completion found")
  eq(nil, item.command)
  eq("[[target#^whole-list]]", item.textEdit.newText)
end

T["completion"]["keeps the cursor on a same-note link after multiline list-item ID insertion"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "- Gemmy\n    $$Paperclip / Pen$$\n\n[[^Paperclip",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 4, 12 })

  local result = run_completion(3, 12)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("Paperclip", 1, true)
  end)
  assert(item, "no current-note multiline list-item completion found")
  accept_completion(item)

  local lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  local block_id = lines[3]:match "^    (%^[0-9a-f]+)$"
  assert(block_id, "same-note list item has no indented block ID")
  eq("[[#" .. block_id .. "]]", lines[5])
  eq({ 5, #lines[5] - 1 }, child.api.nvim_win_get_cursor(0))
end

T["completion"]["separates quotations from preceding list items"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^quoted target",
    ["target.md"] = "- list item\n> quoted target\n> continuation",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 17 })

  local result = run_completion(0, 17)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("quoted target", 1, true)
  end)
  assert(item, "no quotation completion found after list")
  eq("> quoted target > continuation — target", item.label)
end

T["completion"]["keeps lazy continuation lines inside quotations"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^lazy continuation",
    ["target.md"] = "> quoted start\nlazy continuation",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 21 })

  local result = run_completion(0, 21)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label:find("lazy continuation", 1, true)
  end)
  assert(item, "no lazy quotation completion found")
  eq("> quoted start lazy continuation — target", item.label)
end

T["completion"]["reuses an existing block ID"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^manual needle",
    ["target.md"] = "A manual needle ^manual",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 17 })

  local result = run_completion(0, 17)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.label == "A manual needle ^manual — target"
  end)
  assert(item, "no existing block completion found")
  eq(nil, item.command)
  eq("[[target#^manual]]", item.textEdit.newText)
  accept_completion(item)

  eq("[[target#^manual]]", child.api.nvim_get_current_line())
  eq("A manual needle ^manual", vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))[1])
end

T["completion"]["places a blockquote ID on its own line"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^quoted",
    ["target.md"] = "> quoted first\n> quoted second",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("quoted first", 1, true)
  end)
  assert(item, "no blockquote completion found")
  eq("> quoted first > quoted second — target", item.label)
  accept_completion(item)

  local lines = vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))
  local second = vim.iter(lines):enumerate():find(function(_, line)
    return line == "> quoted second"
  end)
  assert(second, "quoted block disappeared")
  eq("", lines[second + 1])
  assert(lines[second + 2]:match "^%^[0-9a-f]+$", "blockquote ID is not standalone")
end

T["completion"]["separates callouts from paragraphs and surrounds their IDs with blank lines"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^Callout body",
    ["target.md"] = "A plain paragraph\n> [!note] Quoted target\n> Callout body\n\nA trailing paragraph",
  })

  child.cmd "set hidden"
  child.cmd("edit " .. tostring(child.Obsidian.dir / "target.md"))
  local target_bufnr = child.api.nvim_get_current_buf()
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 16 })

  local result = run_completion(0, 16)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("Callout body", 1, true)
  end)
  assert(item, "no callout completion found")
  eq("> [!note] Quoted target > Callout body — target", item.label)
  accept_completion(item)

  local lines = child.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
  local block_id = lines[5] and lines[5]:match "^%^[0-9a-f]+$"
  assert(block_id, "callout ID is not surrounded by blank lines")
  eq(
    { "A plain paragraph", "> [!note] Quoted target", "> Callout body", "", block_id, "", "A trailing paragraph" },
    lines
  )
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["places a table ID on its own line"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^value",
    ["target.md"] = "Key | Value\n--- | ---\nOne | Two",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 9 })

  local result = run_completion(0, 9)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("Key | Value", 1, true)
  end)
  assert(item, "no table completion found")
  eq("Key | Value --- | --- One | Two — target", item.label)
  accept_completion(item)

  local lines = vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))
  local last_row = vim.iter(lines):enumerate():find(function(_, line)
    return line == "One | Two"
  end)
  assert(last_row, "table disappeared")
  eq("", lines[last_row + 1])
  assert(lines[last_row + 2]:match "^%^[0-9a-f]+$", "table ID is not standalone")
end

T["completion"]["separates tables from adjacent paragraphs"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^plain target",
    ["target.md"] = "Key | Value\n--- | ---\nOne | Two\nA plain target",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 16 })

  local result = run_completion(0, 16)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label:find("plain target", 1, true)
  end)
  assert(item, "no paragraph completion found after table")
  eq("A plain target — target", item.label)
  accept_completion(item)

  local lines = vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))
  local target_line = vim.iter(lines):find(function(line)
    return vim.startswith(line, "A plain target")
  end)
  assert(target_line, "paragraph after table disappeared")
  local block_id = target_line:match "(%^[0-9a-f]+)$"
  assert(block_id, "paragraph after table did not receive an inline ID")
  eq("A plain target " .. block_id, target_line)
  eq("[[target#" .. block_id .. "]]", child.api.nvim_get_current_line())
end

T["completion"]["keeps list-like rows inside tables"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^foo",
    ["target.md"] = "Name | Value\n--- | ---\n- foo | bar",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  assert(
    vim.iter(result.items or {}):any(function(candidate)
      return candidate.label == "Name | Value --- | --- - foo | bar — target"
    end),
    "no complete table candidate found"
  )
  assert(not vim.iter(result.items or {}):any(function(candidate)
    return candidate.label == "- foo | bar — target"
  end), "table row was exposed as a list-item candidate")
end

T["completion"]["updates a loaded unsaved target without overwriting it"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^needle",
    ["target.md"] = "Old on-disk paragraph",
  })

  child.cmd "set hidden"
  child.cmd("edit " .. tostring(child.Obsidian.dir / "target.md"))
  local target_bufnr = child.api.nvim_get_current_buf()
  child.api.nvim_buf_set_lines(target_bufnr, 0, 1, false, { "Unsaved needle paragraph" })
  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "Unsaved needle paragraph — target"
  end)
  assert(item, "completion ignored the loaded target buffer")
  accept_completion(item)

  local target_line = child.api.nvim_buf_get_lines(target_bufnr, 0, 1, false)[1]
  assert(target_line:match "^Unsaved needle paragraph %^[0-9a-f]+$", "unsaved target was not updated")
  eq(true, child.api.nvim_get_option_value("modified", { buf = target_bufnr }))
  eq("Old on-disk paragraph", vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))[1])
end

T["completion"]["does not create a dangling link when the target changes"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^needle",
    ["target.md"] = "A needle paragraph\n\nA needle paragraph",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.command.arguments[1].target_range.start.line == 2
  end)
  assert(item, "no second duplicate-block completion found")

  vim.fn.writefile(
    { "A needle paragraph", "", "A needle paragraph", "", "A needle paragraph" },
    tostring(child.Obsidian.dir / "target.md")
  )
  accept_completion(item)

  eq("[[^^needle", child.api.nvim_get_current_line())
  eq(5, #vim.fn.readfile(tostring(child.Obsidian.dir / "target.md")))
end

T["completion"]["does not link when the target save fails"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^needle",
    ["target.md"] = "A needle paragraph",
  })
  child.lua [[
    require("obsidian.log").err = function() end
    vim.api.nvim_create_autocmd("BufWritePre", {
      pattern = "target.md",
      callback = function()
        error("expected write failure")
      end,
    })
  ]]

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  local result = run_completion(0, 10)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.command.command == "obsidian.block_reference_new"
  end)
  assert(item, "no unlabeled block completion found")
  accept_completion(item)

  eq("[[^^needle", child.api.nvim_get_current_line())
  eq("A needle paragraph", vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))[1])
end

T["completion"]["searches beyond the configured note line cap"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^deep needle",
    ["target.md"] = "First line\n\nDeep needle paragraph",
  })
  child.lua [[Obsidian.opts.search.max_lines = 1]]

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 15 })

  local result = run_completion(0, 15)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "Deep needle paragraph — target"
  end)
  assert(item, "block completion stopped at search.max_lines")
end

T["completion"]["avoids generated block ID collisions"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^",
    ["target.md"] = "First paragraph\n\nSecond paragraph",
  })
  child.lua [[
    _G.obsidian_test_sha256 = vim.fn.sha256
    vim.fn.sha256 = function(value)
      return string.rep(vim.endswith(value, ":1") and "b" or "a", 64)
    end
  ]]

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 4 })
  local result = run_completion(0, 4)
  child.lua [[
    vim.fn.sha256 = _G.obsidian_test_sha256
    _G.obsidian_test_sha256 = nil
  ]]

  local ids = vim
    .iter(result.items or {})
    :filter(function(item)
      return item.command and vim.endswith(item.label, "— target")
    end)
    :map(function(item)
      return item.command.arguments[1].block_id
    end)
    :totable()
  table.sort(ids)
  eq({ "^aaaaaa", "^bbbbbb" }, ids)
end

T["completion"]["preserves trailing whitespace in the target block"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[^^trailing",
    ["target.md"] = "Trailing paragraph  ",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "source.md"))
  child.api.nvim_win_set_cursor(0, { 1, 12 })
  local result = run_completion(0, 12)
  local item = vim.iter(result.items or {}):find(function(candidate)
    return candidate.command and candidate.label == "Trailing paragraph — target"
  end)
  assert(item, "no trailing-whitespace block completion found")
  accept_completion(item)

  local target_line = vim.iter(vim.fn.readfile(tostring(child.Obsidian.dir / "target.md"))):find(function(line)
    return vim.startswith(line, "Trailing paragraph")
  end)
  assert(target_line, "target paragraph disappeared")
  assert(target_line:match "^Trailing paragraph   %^[0-9a-f]+$", "target whitespace was not preserved")
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

T["completion"]["new-note suggestions do not create notes while typing"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[brandnewnote",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 14 })
  child.lua [[
    _G.obsidian_completion_create_count = 0
    Obsidian.opts.callbacks.create_note = function()
      _G.obsidian_completion_create_count = _G.obsidian_completion_create_count + 1
    end
  ]]

  local result = run_completion(0, 14)
  local create_item = vim.iter(result.items or {}):find(function(item)
    return item.command and item.command.command == "obsidian.write_note"
  end)

  assert(create_item, "no create item found")
  eq(0, child.lua_get "_G.obsidian_completion_create_count")
end

T["completion"]["invalid partial filenames do not prompt during completion"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[bad:name",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 10 })
  child.lua [[
    Obsidian.opts.note_id_func = function(title)
      return title
    end
    _G.obsidian_completion_input_count = 0
    require("obsidian.api").input = function()
      _G.obsidian_completion_input_count = _G.obsidian_completion_input_count + 1
      return "replacement"
    end
  ]]

  local result = run_completion(0, 10)
  eq(0, child.lua_get "_G.obsidian_completion_input_count")
  eq(
    false,
    vim.iter(result.items or {}):any(function(item)
      return item.command and item.command.command == "obsidian.write_note"
    end)
  )
end

T["completion"]["existing note match sorts before create item for the same title"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = "[[Title",
    ["Title.md"] = [==[
---
id: Title
aliases: []
tags: []
---
Existing note content
]==],
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "test.md"))
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  local result = run_completion(0, 7)
  eq("table", type(result))

  local existing_idx, create_idx
  for i, item in ipairs(result.items or {}) do
    if item.command and item.command.command == "obsidian.write_note" then
      create_idx = i
    elseif item.label == "[[Title]]" then
      existing_idx = i
    end
  end

  assert(existing_idx, "no existing-note item found")
  assert(create_idx, "no create item found")
  assert(existing_idx < create_idx, "existing note item should sort before create item")
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
