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
    ["target.md"] = "[[existing]]",
  })
  child.cmd("edit " .. files["referencer.md"])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.lua "vim.lsp.buf.definition()"
  h.child_wait_for_buf_name(child, files["target.md"])
  eq({ 1, 0 }, child.api.nvim_win_get_cursor(0))
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

T["creating a missing definition refreshes its diagnostic"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = "[[target]]",
  })
  child.lua [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    assert(vim.wait(1000, function()
      return cache.is_ready()
    end))
  ]]
  child.cmd("edit " .. files["referencer.md"])
  child.lua "_G.referencer_buf = vim.api.nvim_get_current_buf()"
  h.child_wait_for_lsp_client(child, "obsidian-ls")
  h.child_wait(
    child,
    [[
    for _, diagnostic in ipairs(vim.diagnostic.get(_G.referencer_buf)) do
      if diagnostic.code == "broken-link" then
        return true
      end
    end
    return false
  ]],
    { desc = "broken-link diagnostic" }
  )

  child.lua [=[
    Obsidian.opts.note_id_func = require("obsidian.builtin").title_id
    require("obsidian.api").confirm = function() return "Yes" end
    require("obsidian.lsp.handlers._definition").follow_link("[[target]]", function()
      _G.definition_created = true
    end, { bufnr = _G.referencer_buf, cursor_row = 1 })
  ]=]

  h.child_wait(child, "return _G.definition_created == true", { desc = "definition creation" })
  h.child_wait_for_path(child, child.Obsidian.dir / "target.md")
  h.child_wait(
    child,
    [[
    for _, diagnostic in ipairs(vim.diagnostic.get(_G.referencer_buf)) do
      if diagnostic.code == "broken-link" then
        return false
      end
    end
    return true
  ]],
    { desc = "broken-link diagnostic to clear" }
  )
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
