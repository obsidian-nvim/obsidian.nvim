local h = dofile "tests/helpers.lua"
local uri = require "obsidian.uri"
local eq = MiniTest.expect.equality

local T = h.temp_vault

local function plain_notes()
  Obsidian.opts.frontmatter.enabled = false
  Obsidian.opts.note.template = nil
end

T["new persists an exact nested file silently"] = function()
  plain_notes()
  local result = uri.handle "obsidian://new?file=Clippings%2FPage%20Title&content=hello%26world&silent"
  local path = Obsidian.dir / "Clippings" / "Page Title.md"

  eq(true, result.ok)
  eq(true, path:is_file())
  eq({ "hello&world" }, h.read(path))
  eq(false, vim.api.nvim_buf_get_name(0) == tostring(path))
end

T["new content does not gain plugin frontmatter or a template"] = function()
  local result = uri.handle "obsidian://new?name=Clipped&content=%23%20Clipped&silent"

  eq(true, result.ok)
  eq({ "# Clipped" }, h.read(Obsidian.dir / "Clipped.md"))
end

T["new creates an empty note when silent"] = function()
  plain_notes()
  local result = uri.handle "obsidian://new?name=Empty&silent"

  eq(true, result.ok)
  eq(true, (Obsidian.dir / "Empty.md"):is_file())
end

T["new leaves existing content unchanged without a mutation flag"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  local result = uri.handle "obsidian://new?file=Existing&content=new&silent"

  eq(true, result.ok)
  eq({ "old" }, h.read(path))
end

T["new appends and append takes precedence over overwrite"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&append&overwrite&silent"

  eq({ "old", "new" }, h.read(path))
end

T["new prepends content"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&prepend&silent"

  eq({ "new", "old" }, h.read(path))
end

T["new overwrites content"] = function()
  plain_notes()
  local path = Obsidian.dir / "Existing.md"
  h.write("old", path)

  uri.handle "obsidian://new?file=Existing&content=new&overwrite&silent"

  eq({ "new" }, h.read(path))
end

T["new rejects traversal outside the workspace"] = function()
  plain_notes()
  local outside = assert(Obsidian.dir:parent(), "temporary vault parent is required") / "outside.md"
  local result = uri.handle "obsidian://new?file=..%2Foutside&content=nope&silent"

  eq(false, result.ok)
  eq(false, outside:exists())
end

T["daily persists content without opening"] = function()
  plain_notes()
  local result = uri.handle "obsidian://daily?content=journal&silent"

  eq(true, result.ok)
  eq(true, result.note:exists())
  eq({ "journal" }, h.read(result.note.path))
  eq(false, vim.api.nvim_buf_get_name(0) == tostring(result.note.path))
end

T["unique uses the configured unique folder"] = function()
  plain_notes()
  Obsidian.opts.unique_note.folder = "unique"
  Obsidian.opts.unique_note.template = nil
  local unique_dir = Obsidian.dir / "unique"
  unique_dir:mkdir()

  local result = uri.handle "obsidian://unique?content=unique%20body"

  eq(true, result.ok)
  eq(unique_dir, result.note.path:parent())
  eq({ "unique body" }, h.read(result.note.path))
end

T["open navigates to block lines"] = function()
  plain_notes()
  local path = Obsidian.dir / "Blocks.md"
  h.write("first\ntarget ^block", path)

  local result = uri.handle "obsidian://open?file=Blocks%23%5Eblock"

  eq(true, result.ok)
  eq(2, vim.api.nvim_win_get_cursor(0)[1])
end

T["open supports paneType tab"] = function()
  plain_notes()
  h.write("body", Obsidian.dir / "Tabbed.md")

  local result = uri.handle "obsidian://open?file=Tabbed&paneType=tab"

  eq(true, result.ok)
  eq(2, #vim.api.nvim_list_tabpages())
end

T["path overrides an invalid vault"] = function()
  plain_notes()
  local path = Obsidian.dir / "Absolute.md"
  h.write("body", path)
  local encoded = vim.uri_encode(tostring(path), "rfc2396")

  local result = uri.handle("obsidian://open?vault=missing&path=" .. encoded)

  eq(true, result.ok)
  eq(tostring(path), vim.api.nvim_buf_get_name(0))
end

T["absolute paths select the most specific workspace"] = function()
  plain_notes()
  local original = Obsidian.workspace
  local nested_dir = Obsidian.dir / "nested"
  nested_dir:mkdir()
  local nested = require("obsidian.workspace").new {
    name = "nested",
    path = nested_dir,
    strict = true,
  }
  assert(nested, "nested workspace is required")
  table.insert(Obsidian.workspaces, nested)
  local path = nested_dir / "Specific.md"
  h.write("body", path)

  local ok, result = pcall(uri.handle, "obsidian://open?path=" .. vim.uri_encode(tostring(path), "rfc2396"))
  require("obsidian.workspace").set(original)

  assert(ok, result)
  eq(true, result.ok)
  eq("nested", result.note.path:parent().name)
end

T["x-success receives note callback parameters"] = function()
  plain_notes()
  local opened
  local original = vim.ui.open
  vim.ui.open = function(value)
    opened = value
  end

  local ok, result = pcall(uri.handle, "obsidian://new?name=Callback&silent&x-success=test%3A%2F%2Fdone")
  vim.ui.open = original

  assert(ok, result)
  eq(true, result.ok)
  eq(true, opened:find("^test://done?", 1) ~= nil)
  eq(true, opened:find("name=Callback", 1, true) ~= nil)
  eq(true, opened:find("url=obsidian%3a%2f%2fopen", 1, true) ~= nil)
end

T["markdown URI handling preserves encoded query delimiters"] = function()
  Obsidian.opts.uri.require_confirmation = false
  local definition = require "obsidian.lsp.handlers._definition"
  local received
  local original = uri.handle
  uri.handle = function(value)
    received = value
    return {
      ok = true,
      action = "new",
      interactive = false,
      silent = false,
    }
  end

  local ok, err = pcall(function()
    definition.follow_link("[URI](obsidian://new?content=a%26b%3Dc)", function() end)
  end)
  uri.handle = original

  assert(ok, err)
  eq("obsidian://new?content=a%26b%3Dc", received)
end

T["markdown mutating URIs require confirmation"] = function()
  Obsidian.opts.uri.require_confirmation = true
  local definition = require "obsidian.lsp.handlers._definition"
  local api = require "obsidian.api"
  local handled = false
  local original_handle = uri.handle
  local original_confirm = api.confirm
  uri.handle = function()
    handled = true
    return {
      ok = true,
      action = "new",
      interactive = false,
      silent = false,
    }
  end
  api.confirm = function()
    return "No"
  end

  local ok, err = pcall(function()
    definition.follow_link("[URI](obsidian://new?name=Blocked)", function() end)
  end)
  uri.handle = original_handle
  api.confirm = original_confirm

  assert(ok, err)
  eq(false, handled)
end

T["unsupported actions return an error result"] = function()
  local result = uri.handle "obsidian://unknown?value=1"
  eq(false, result.ok)
  eq("unknown", result.action)
end

return T
