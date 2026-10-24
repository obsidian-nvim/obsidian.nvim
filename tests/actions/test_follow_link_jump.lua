local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["follow link returns to the exact source position with <C-o>"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "first line\ntext [[target]] after\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.cmd "normal! m'" -- An older jump must not be the first stop on the way back.
  child.api.nvim_win_set_cursor(0, { 2, 8 })

  child.lua [[require("obsidian.actions").follow_link()]]
  h.child_wait_for_buf_name(child, files["target.md"])
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 2, 8 }, child.api.nvim_win_get_cursor(0))
end

T["follow link to heading in the same note returns to link with <C-o>"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "# Heading\nother line\ntext [[#Heading]] after\n",
  })
  child.cmd("edit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 2, 2 })
  child.cmd "normal! m'"
  child.api.nvim_win_set_cursor(0, { 3, 8 })

  child.lua [[require("obsidian.actions").follow_link()]]
  h.child_wait(child, [[return vim.api.nvim_win_get_cursor(0)[1] == 1]], { desc = "heading jump" })
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 3, 8 }, child.api.nvim_win_get_cursor(0))
end

T["follow link to an already visible note returns to link with <C-o>"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "first line\ntext [[target]] after\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["target.md"])
  child.cmd("vsplit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.cmd "normal! m'"
  child.api.nvim_win_set_cursor(0, { 2, 8 })

  child.lua [[require("obsidian.actions").follow_link()]]
  h.child_wait_for_buf_name(child, files["target.md"])
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 2, 8 }, child.api.nvim_win_get_cursor(0))
end

T["follow link with split strategy returns to link with <C-o>"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "first line\ntext [[target]] after\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.cmd "normal! m'"
  child.api.nvim_win_set_cursor(0, { 2, 8 })

  child.lua [[require("obsidian.actions").follow_link(nil, { open_strategy = "vsplit" })]]
  h.child_wait_for_buf_name(child, files["target.md"])
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 2, 8 }, child.api.nvim_win_get_cursor(0))
end

T["follow link with split strategy to a visible note returns to link with <C-o>"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = "first line\ntext [[target]] after\n",
    ["target.md"] = "destination\n",
  })
  child.cmd("edit " .. files["target.md"])
  child.cmd("vsplit " .. files["source.md"])
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.cmd "normal! m'"
  child.api.nvim_win_set_cursor(0, { 2, 8 })

  child.lua [[require("obsidian.actions").follow_link(nil, { open_strategy = "vsplit" })]]
  h.child_wait_for_buf_name(child, files["target.md"])
  child.lua [[vim.api.nvim_feedkeys(vim.keycode("<C-o>"), "nx", false)]]
  eq(files["source.md"], child.api.nvim_buf_get_name(0))
  eq({ 2, 8 }, child.api.nvim_win_get_cursor(0))
end

return T
