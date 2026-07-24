local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function open_note()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["note.md"] = "# Note",
  })
  child.cmd("edit " .. files["note.md"])
end

T["popup menu"] = MiniTest.new_set()

T["popup menu"]["keeps default entries and adds actions directly"] = function()
  open_note()
  child.lua [[vim.api.nvim_exec_autocmds("MenuPopup", { pattern = "n" })]]

  local popup = child.lua_get [[vim.fn.menu_info("PopUp").submenus]]
  eq(true, vim.list_contains(popup, "Paste"))
  eq(true, vim.list_contains(popup, "add_property"))
  eq(true, vim.list_contains(popup, "insert_template"))
  eq(false, vim.list_contains(popup, "link"))

  local action = child.lua_get [[vim.fn.menu_info("PopUp.add_property")]]
  eq("a", action.modes)
  eq(false, action.submenus ~= nil)
end

T["popup menu"]["uses custom conditions and action names"] = function()
  open_note()
  child.lua [[
    require("obsidian").code_action.add {
      name = "popup_test_hidden",
      title = "Hidden popup action",
      cond = function()
        return false
      end,
      fn = function() end,
    }
    require("obsidian").code_action.add {
      name = "popup_test_dynamic",
      title = function(note)
        return "Custom action for " .. note.id .. ".md"
      end,
      fn = function()
        vim.g.obsidian_popup_test_executed = true
      end,
    }
    vim.api.nvim_exec_autocmds("MenuPopup", { pattern = "n" })
  ]]

  local popup = child.lua_get [[vim.fn.menu_info("PopUp").submenus]]
  eq(false, vim.list_contains(popup, "popup_test_hidden"))
  eq(true, vim.list_contains(popup, "popup_test_dynamic"))

  child.cmd "emenu PopUp.popup_test_dynamic"
  h.child_wait(child, [[return vim.g.obsidian_popup_test_executed == true]], { desc = "custom popup action" })
end

T["popup menu"]["adds visual actions for a visual selection"] = function()
  open_note()
  child.cmd "normal! gg0v$"
  child.lua [[vim.api.nvim_exec_autocmds("MenuPopup", { pattern = "v" })]]

  local popup = child.lua_get [[vim.fn.menu_info("PopUp").submenus]]
  eq(true, vim.list_contains(popup, "link"))
  eq(true, vim.list_contains(popup, "link_new"))
  eq(true, vim.list_contains(popup, "extract_note"))
end

T["popup menu"]["is removed outside Obsidian buffers"] = function()
  open_note()
  child.lua [[vim.api.nvim_exec_autocmds("MenuPopup", { pattern = "n" })]]
  eq(true, vim.list_contains(child.lua_get [[vim.fn.menu_info("PopUp").submenus]], "add_property"))

  child.cmd "enew"
  child.lua [[vim.api.nvim_exec_autocmds("MenuPopup", { pattern = "n" })]]
  local popup = child.lua_get [[vim.fn.menu_info("PopUp").submenus]]
  eq(false, vim.list_contains(popup, "add_property"))
  eq(true, vim.list_contains(popup, "Paste"))
end

return T
