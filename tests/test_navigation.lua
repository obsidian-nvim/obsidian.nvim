local h = dofile "tests/helpers.lua"
local eq = MiniTest.expect.equality
local T, child = h.child_vault {
  pre_case = [[M = require "obsidian.navigation"]],
}

T["open_note blinks quickfix-style ranges"] = function()
  local result = child.lua [[
    local path = tostring(Obsidian.dir / "blink.md")
    vim.fn.writefile({ "# Heading", "body" }, path)
    local bufnr = M.open_note({ filename = path, lnum = 1, col = 1, end_lnum = 2, end_col = 5 })
    local blinked = false
    for name, ns in pairs(vim.api.nvim_get_namespaces()) do
      if name:match("^obsidian_blink_") and #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {}) > 0 then
        blinked = true
      end
    end
    return { vim.api.nvim_buf_get_name(bufnr), vim.api.nvim_win_get_cursor(0), blinked }
  ]]

  eq(tostring(child.Obsidian.dir / "blink.md"), result[1])
  eq({ 1, 0 }, result[2])
  eq(true, result[3])
end

T["open_buffer preserves zero-based columns"] = function()
  local result = child.lua [[
    local path = Obsidian.dir / "buffer.md"
    vim.fn.writefile({ "first line", "second line" }, tostring(path))
    local bufnr = M.open_buffer(path, { line = 2, col = 3, cmd = "vsplit" })
    return { vim.api.nvim_buf_get_name(bufnr), vim.api.nvim_win_get_cursor(0), #vim.api.nvim_list_wins() }
  ]]

  eq(tostring(child.Obsidian.dir / "buffer.md"), result[1])
  eq({ 2, 3 }, result[2])
  eq(2, result[3])
end

T["get_open_strategy selects commands for a single window"] = function()
  eq(
    { "e ", "tabedit ", "split ", "vsplit ", "split ", "vsplit " },
    child.lua [[return {
      M.get_open_strategy("current"),
      M.get_open_strategy("tab"),
      M.get_open_strategy("hsplit"),
      M.get_open_strategy("vsplit"),
      M.get_open_strategy("hsplit_force"),
      M.get_open_strategy("vsplit_force"),
    }]]
  )
end

T["get_open_strategy reuses an existing matching layout unless forced"] = function()
  child.cmd "vsplit"
  eq(
    { "e ", "vsplit " },
    child.lua [[return {
    M.get_open_strategy("vsplit"), M.get_open_strategy("vsplit_force"),
  }]]
  )
  child.cmd "only"
  child.cmd "split"
  eq(
    { "e ", "split " },
    child.lua [[return {
    M.get_open_strategy("hsplit"), M.get_open_strategy("hsplit_force"),
  }]]
  )
end

T["follow_link command resolves directly without vim.lsp.buf.definition"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "text [[target]] after\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 1, 8 })
  child.lua [[vim.lsp.buf.definition = function() error("must not request LSP definition") end]]
  child.cmd "Obsidian follow_link vsplit_force"
  h.child_wait_for_buf_name(child, files["target.md"])
  eq(2, #child.api.nvim_list_wins())
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-t>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 1, 8 }, child.api.nvim_win_get_cursor(0))
end

T["follow_link uses the configured strategy and forced horizontal split is valid"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[target]]\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["source.md"])
  child.cmd "split"
  child.lua [[
    Obsidian.opts.open_notes_in = "hsplit_force"
    require("obsidian.commands.follow_link") { args = "" }
  ]]
  h.child_wait_for_buf_name(child, files["target.md"])
  eq(3, #child.api.nvim_list_wins())
end

T["follow_link with no link or invalid input never opens a picker"] = function()
  eq(
    true,
    child.lua [[
    require("obsidian.picker").select = function() error("unexpected picker") end
    M.follow_link()
    M.follow_link("not a link")
    return true
  ]]
  )
end

T["resolve_link returns locations without jumping or mutating options"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "[[target]]\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["source.md"])
  local result = h.child_await(
    child,
    [=[
    local opts = { bufnr = vim.api.nvim_get_current_buf() }
    M.resolve_link("[[target]]", function(err, locations)
      assert(not err)
      done({ #locations, vim.uri_to_fname(locations[1].uri), opts.anchor, opts.cursor_row })
    end, opts)
  ]=]
  )
  eq(1, result[1])
  eq(files["target.md"], result[2])
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq(nil, result[3])
  eq(nil, result[4])
end

T["jump_to_locations selects among distinct targets in the same note"] = function()
  eq(
    { 2, 2, 1, "vsplit ", true },
    child.lua [[
    local path = tostring(Obsidian.dir / "targets.md")
    vim.fn.writefile({ "first", "second" }, path)
    local locations = {
      { uri = vim.uri_from_fname(path), range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } } },
      { uri = vim.uri_from_fname(path), range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 3 } } },
    }
    local count, row, col, command, same_location
    M.jump_to_note = function(entry, cmd)
      row, col, command = entry.lnum, entry.col, cmd
      same_location = entry.user_data == locations[2]
    end
    require("obsidian.picker").select = function(items, opts, callback)
      count = #items
      local preview = opts.preview_item(items[2])
      assert(preview.pos[1] == 2)
      assert(preview.pos_end[1] == 2)
      callback { items[2] }
    end
    M.jump_to_locations(locations, { open_strategy = "vsplit_force" })
    return { count, row, col, command, same_location }
  ]]
  )
end

T["jump_to_locations handles no results and picker cancellation"] = function()
  eq(
    1,
    child.lua [[
    M.jump_to_note = function() error("unexpected jump") end
    local picks = 0
    require("obsidian.picker").select = function(_, _, callback)
      picks = picks + 1
      callback(nil)
      callback({})
    end
    M.jump_to_locations({})
    local uri = vim.uri_from_fname(tostring(Obsidian.dir / "target.md"))
    local location = { uri = uri, range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } } }
    M.jump_to_locations({ location, location })
    return picks
  ]]
  )
end

T["links picker uses navigation and handles cancellation"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["source.md"] = "[[target]]\n" })
  child.cmd("edit " .. files["source.md"])
  eq(
    "[[target]]",
    child.lua [[
    local followed
    M.follow_link = function(link) followed = link end
    require("obsidian.picker").select = function(items, _, callback)
      callback(nil)
      callback({})
      callback { items[1] }
    end
    require("obsidian.commands.links")()
    return followed
  ]]
  )
end

T["resolve_link completes external and missing local targets with no locations"] = function()
  eq(
    { 3, 1 },
    child.lua [=[
    local callbacks, opened = 0, 0
    vim.ui.open = function() opened = opened + 1 end
    local function callback(err, locations)
      assert(not err and #locations == 0)
      callbacks = callbacks + 1
    end
    M.resolve_link("[[#Missing]]", callback)
    M.resolve_link("[[#^missing]]", callback)
    M.resolve_link("[website](https://example.com)", callback)
    return { callbacks, opened }
  ]=]
  )
end

T["nav_link moves between links and is not exposed as an action"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["source.md"] = "[[first]] text [[second]]\n" })
  child.cmd("edit " .. files["source.md"])
  child.lua [[M.nav_link("next")]]
  eq({ 1, 15 }, child.api.nvim_win_get_cursor(0))
  child.lua [[M.nav_link("prev")]]
  eq({ 1, 0 }, child.api.nvim_win_get_cursor(0))
  eq(true, child.lua [[return require("obsidian.actions").nav_link == nil]])
end

T["default link keymaps use navigation directly"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["source.md"] = "[[first]] text [[second]]\n" })
  child.cmd("edit " .. files["source.md"])
  eq(
    { { "next", true }, { "prev", true } },
    child.lua [[
    local calls = {}
    M.nav_link = function(direction, hints) calls[#calls + 1] = { direction, hints } end
    for _, lhs in ipairs({ "]o", "[o" }) do
      local mapping = vim.fn.maparg(lhs, "n", false, true)
      assert(mapping.buffer == 1)
      mapping.callback()
    end
    return calls
  ]]
  )
end

T["following a missing relative note creates it relative to the source"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["nested/source.md"] = "[[./created]]\n" })
  child.cmd("edit " .. files["nested/source.md"])
  child.lua [[
    Obsidian.opts.note_id_func = function(id) return id end
    require("obsidian.api").confirm = function() return "Yes" end
    M.follow_link()
  ]]
  h.child_wait_for_buf_name(child, tostring(child.Obsidian.dir / "nested" / "created.md"))
end

return T
