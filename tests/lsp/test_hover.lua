local h = dofile "tests/helpers.lua"
local eq = MiniTest.expect.equality
local T, child = h.child_vault()

local function hover_contents()
  child.lua [[
    _G.hover_result = nil
    require("obsidian.lsp.handlers.hover")(nil, function(_, hover)
      _G.hover_result = hover
    end, nil)
  ]]
  return child.lua_get "_G.hover_result and _G.hover_result.contents or nil"
end

local function expect_hover_contains(needle)
  local contents = hover_contents()
  assert(contents, "expected hover contents")
  assert(contents:find(needle, 1, true), ("expected hover to contain %q, got:\n%s"):format(needle, contents))
end

T["emits an event for hover buffers"] = function()
  child.lua [[
    _G.hover_event = nil
    vim.api.nvim_create_autocmd("User", {
      pattern = "ObsidianHover",
      callback = function(ev)
        _G.hover_event = ev.data
      end,
    })

    local source_buf = vim.api.nvim_get_current_buf()
    local hover_buf, hover_win = vim.lsp.util.open_floating_preview(
      { "![image](" .. vim.fn.getcwd() .. "/image.png)" },
      "markdown",
      { focus_id = "textDocument/hover", close_events = {} }
    )
    _G.hover_ids = { source_buf = source_buf, buf = hover_buf, win = hover_win }
  ]]

  h.child_wait(child, "return _G.hover_event ~= nil", { desc = "ObsidianHover event" })
  eq(child.lua_get "_G.hover_event.buf", child.lua_get "_G.hover_ids.buf")
  eq(child.lua_get "_G.hover_event.win", child.lua_get "_G.hover_ids.win")
  eq(child.lua_get "_G.hover_event.source_buf", child.lua_get "_G.hover_ids.source_buf")

  child.lua [[vim.api.nvim_win_close(_G.hover_ids.win, true)]]
end

T["previews links"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[[[target]]
[target](./target.md)
[[target#Heading]]
[[target#^block]]
[[#Local Heading]]
[[#^local-block]]
footnote[^1]
Local block text ^local-block
## Local Heading
[^1]: footnote text]==],
    ["target.md"] = [==[## Heading

Target block text ^block]==],
  })

  child.cmd("edit " .. files["referencer.md"])

  child.api.nvim_win_set_cursor(0, { 1, 2 })
  expect_hover_contains "**id:** `target`"

  child.api.nvim_win_set_cursor(0, { 2, 2 })
  expect_hover_contains "**id:** `target`"

  child.api.nvim_win_set_cursor(0, { 3, 2 })
  expect_hover_contains "## Heading"

  child.api.nvim_win_set_cursor(0, { 4, 2 })
  expect_hover_contains "Target block text ^block"

  child.api.nvim_win_set_cursor(0, { 5, 2 })
  expect_hover_contains "## Local Heading"

  child.api.nvim_win_set_cursor(0, { 6, 2 })
  expect_hover_contains "Local block text ^local-block"

  child.api.nvim_win_set_cursor(0, { 7, 10 })
  expect_hover_contains "[^1]: footnote text"

  child.api.nvim_win_set_cursor(0, { 8, 17 })
  expect_hover_contains "Local block text ^local-block"
end

return T
