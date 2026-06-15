local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local fs_eq = function(a, b)
  local normalize = vim.fs.normalize
  eq(normalize(a), normalize(b))
end

T["follow wiki links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[

[[target]]
]==],
    ["target.md"] = "",
  })
  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  h.child_wait_for_buf_name(child, files["target.md"])
end

T["wiki links resolve by basename/stem only"] = function()
  (child.Obsidian.dir / "notes"):mkdir()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = "[[target]]",
    ["target.md"] = "",
    ["notes/target.md"] = "",
  })

  child.cmd("edit " .. files["referencer.md"])
  local locations = h.child_await(
    child,
    [=[
    require("obsidian.lsp.handlers._definition").follow_link("[[target]]", function(_, result)
      done(result)
    end, {})
  ]=]
  )

  eq(2, #locations)
  local paths = vim.tbl_map(function(location)
    return vim.fs.normalize(vim.uri_to_fname(location.uri))
  end, locations)
  eq(true, vim.list_contains(paths, vim.fs.normalize(files["target.md"])))
  eq(true, vim.list_contains(paths, vim.fs.normalize(files["notes/target.md"])))
end

T["wiki links do not resolve aliases"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = "[[Alias]]",
    ["aliased.md"] = "---\naliases:\n  - Alias\n---\n",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "referencer.md"))
  local result = h.child_await(
    child,
    [=[
    local api = require "obsidian.api"
    local done_called = false
    local callback_called = false
    api.confirm = function(prompt)
      if not done_called then
        done_called = true
        done({ callback_called = callback_called, prompt = prompt })
      end
      return "No"
    end
    require("obsidian.lsp.handlers._definition").follow_link("[[Alias]]", function()
      callback_called = true
      if not done_called then
        done_called = true
        done({ callback_called = callback_called })
      end
    end, {})
  ]=]
  )

  eq(false, result.callback_called)
  eq("Create new note 'Alias'?", result.prompt)
end

T["wiki links do not resolve fuzzy matches"] = function()
  h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = "[[foo]]",
    ["not-foo.md"] = "",
  })

  child.cmd("edit " .. tostring(child.Obsidian.dir / "referencer.md"))
  local result = h.child_await(
    child,
    [=[
    local api = require "obsidian.api"
    local done_called = false
    local callback_called = false
    api.confirm = function(prompt)
      if not done_called then
        done_called = true
        done({ callback_called = callback_called, prompt = prompt })
      end
      return "No"
    end
    require("obsidian.lsp.handlers._definition").follow_link("[[foo]]", function()
      callback_called = true
      if not done_called then
        done_called = true
        done({ callback_called = callback_called })
      end
    end, {})
  ]=]
  )

  eq(false, result.callback_called)
  eq("Create new note 'foo'?", result.prompt)
end

T["follow markdown links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[

[target](./target.md)
]==],
    ["target.md"] = "",
  })

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  h.child_wait_for_buf_name(child, files["target.md"])
end

T["follow encoded headerlinks"] = function()
  local src = [==[
## This is a heading with spaces

[`some code`](#This%20is%20a%20heading%20with%20spaces)

[[#This is a heading with spaces|`some code`]]
]==]
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["test.md"] = src,
  })
  child.cmd("edit " .. files["test.md"])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(child.api.nvim_win_get_cursor(0), { 1, 0 })
  child.api.nvim_win_set_cursor(0, { 5, 0 })
  child.lua "vim.lsp.buf.definition()"
  eq(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

T["goto footnote definition"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["note.md"] = [==[
some claim[^1]

more text

[^1]: the footnote
]==],
  })
  child.cmd("edit " .. files["note.md"])
  child.api.nvim_win_set_cursor(0, { 1, 11 })
  child.lua "vim.lsp.buf.definition()"
  h.wait(function()
    return vim.deep_equal(child.api.nvim_win_get_cursor(0), { 5, 0 })
  end, { desc = "cursor on footnote definition" })
end

T["goto first footnote reference from definition"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["note.md"] = [==[
some claim[^1]

[^1]: the footnote
]==],
  })
  child.cmd("edit " .. files["note.md"])
  child.api.nvim_win_set_cursor(0, { 3, 0 })
  child.lua "vim.lsp.buf.definition()"
  h.wait(function()
    return vim.deep_equal(child.api.nvim_win_get_cursor(0), { 1, 10 })
  end, { desc = "cursor on first footnote reference" })
end

local filetypes = require("obsidian.attachment").filetypes

local function test_ft(ext)
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = ([==[

[target](./target.%s)
]==]):format(ext),
  })

  child.lua [[
  vim.ui.open = function(uri)
    _G.uri = uri
  end
  ]]

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  fs_eq(tostring(child.Obsidian.dir / "attachments" / ("target." .. ext)), child.lua_get "uri")
end

T["open attachment"] = function()
  for _, ft in ipairs(filetypes) do
    if ft ~= "md" then
      test_ft(ft)
    end
  end
end

T["follow uris"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = ([==[

[test](file://%s/test.lua)
]==]):format(tostring(child.Obsidian.dir)),
    ["test.lua"] = "",
  })

  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua [[
  vim.ui.open = function(uri)
     _G.uri = uri
  end
  ]]
  child.lua "vim.lsp.buf.definition()"
  fs_eq(files["test.lua"], vim.uri_to_fname(child.lua_get "uri"))
end

return T
