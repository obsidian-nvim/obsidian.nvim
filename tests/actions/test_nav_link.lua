local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function setup_note()
  local files = h.child_mock_vault_contents(child, {
    ["current.md"] = "a target then [[actual]]",
    ["target.md"] = "",
  })
  child.cmd("edit " .. files["current.md"])
end

T["nav_link includes link suggestion hints when requested and cache is enabled"] = function()
  setup_note()
  h.child_setup_cache(child)

  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[require("obsidian.actions").nav_link("next", true)]]
  eq({ 1, 2 }, child.api.nvim_win_get_cursor(0))

  child.lua [[require("obsidian.actions").nav_link("next", true)]]
  eq({ 1, 14 }, child.api.nvim_win_get_cursor(0))

  child.lua [[require("obsidian.actions").nav_link("prev", true)]]
  eq({ 1, 2 }, child.api.nvim_win_get_cursor(0))
end

T["nav_link ignores link suggestion hints by default"] = function()
  setup_note()
  h.child_setup_cache(child)

  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[require("obsidian.actions").nav_link "next"]]
  eq({ 1, 14 }, child.api.nvim_win_get_cursor(0))
end

T["nav_link ignores requested hints when cache is disabled"] = function()
  setup_note()

  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.lua [[require("obsidian.actions").nav_link("next", true)]]
  eq({ 1, 14 }, child.api.nvim_win_get_cursor(0))
end

return T
