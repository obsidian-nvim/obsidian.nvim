local h = dofile "tests/helpers.lua"
local T, child = h.child_vault {
  pre_case = [[M = require"obsidian.api"]],
}
local eq = MiniTest.expect.equality

T["cursor_link returns range"] = function()
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "The [[new note]] link" })
  child.api.nvim_win_set_cursor(0, { 1, 5 })
  local link, t, range = unpack(child.lua_get [[{ M.cursor_link() }]])
  eq("[[new note]]", link)
  eq("Wiki", t)
  eq({ 5, 16 }, range)
end

T["follow link to non-existing note and create it"] = function()
  child.lua [[
    Obsidian.opts.note_id_func = function(title)
      return "fixed-id-" .. (title or "none")
    end
    M.confirm = function()
      return "Yes"
    end
  ]]

  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[
[[new note]]
]==],
  })

  child.cmd("edit " .. files["referencer.md"])
  local ref_bufnr = child.api.nvim_get_current_buf()
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Trigger follow_link via actions.follow_link which is accessible via M.follow_link
  child.lua "M.follow_link()"

  -- Switch back to the referencer buffer to check content
  local lines = child.api.nvim_buf_get_lines(ref_bufnr, 0, -1, false)
  eq("[[fixed-id-new note|new note]]", lines[1])

  -- Check if the new note was opened
  local current_buf_name = child.api.nvim_buf_get_name(0)
  assert(current_buf_name:match "fixed%-id%-new note%.md$", "New note should be opened, but got " .. current_buf_name)
end

T["follow link with alias to non-existing note and create it"] = function()
  child.lua [[
    Obsidian.opts.note_id_func = function(title)
      return "fixed-id-" .. (title or "none")
    end
    M.confirm = function()
      return "Yes"
    end
  ]]

  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[
[[new note|some alias]]
]==],
  })

  child.cmd("edit " .. files["referencer.md"])
  local ref_bufnr = child.api.nvim_get_current_buf()
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Trigger follow_link via actions.follow_link which is accessible via M.follow_link
  child.lua "M.follow_link()"

  -- Switch back to the referencer buffer to check content
  local lines = child.api.nvim_buf_get_lines(ref_bufnr, 0, -1, false)
  eq("[[fixed-id-new note|some alias]]", lines[1])
end

T["follow link with anchor to non-existing note and create it"] = function()
  child.lua [[
    Obsidian.opts.note_id_func = function(title)
      return "fixed-id-" .. (title or "none")
    end
    M.confirm = function()
      return "Yes"
    end
  ]]

  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["referencer.md"] = [==[
[[new note#Some Header]]
]==],
  })

  child.cmd("edit " .. files["referencer.md"])
  local ref_bufnr = child.api.nvim_get_current_buf()
  child.api.nvim_win_set_cursor(0, { 1, 0 })

  -- Trigger follow_link
  child.lua "M.follow_link()"

  -- The link should be updated to point to the new ID,
  -- but keep the anchor and the original title as the alias.
  local lines = child.api.nvim_buf_get_lines(ref_bufnr, 0, -1, false)
  eq("[[fixed-id-new note#Some Header|new note#Some Header]]", lines[1])

  -- Check if the new note was actually opened (ignoring the anchor for the filename)
  local current_buf_name = child.api.nvim_buf_get_name(0)
  assert(current_buf_name:match "fixed%-id%-new note%.md$", "New note should be opened, but got " .. current_buf_name)
end

return T
