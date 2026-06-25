local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["delete_note removes file and wipes current buffer"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["delete-me.md"] = "# Delete me",
  })

  child.cmd("edit " .. vim.fn.fnameescape(files["delete-me.md"]))
  local bufnr = child.api.nvim_get_current_buf()

  child.lua [[
    local api = require "obsidian.api"
    api.confirm = function()
      return "Yes"
    end
    require("obsidian.actions").delete_note()
  ]]

  eq(nil, vim.uv.fs_stat(files["delete-me.md"]))
  eq(false, child.api.nvim_buf_is_valid(bufnr))
end

T["delete_note keeps file and buffer when cancelled"] = function()
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["keep-me.md"] = "# Keep me",
  })

  child.cmd("edit " .. vim.fn.fnameescape(files["keep-me.md"]))
  local bufnr = child.api.nvim_get_current_buf()

  child.lua [[
    local api = require "obsidian.api"
    api.confirm = function()
      return "No"
    end
    require("obsidian.actions").delete_note()
  ]]

  assert(vim.uv.fs_stat(files["keep-me.md"]), "note file should still exist")
  eq(true, child.api.nvim_buf_is_valid(bufnr))
  eq(vim.fs.normalize(files["keep-me.md"]), vim.fs.normalize(child.api.nvim_buf_get_name(bufnr)))
end

T["delete_note is registered as a code action"] = function()
  child.lua [[
    local actions = require("obsidian.lsp.handlers._code_action").actions
    _G.delete_note_action = actions.delete_note
  ]]

  eq("Delete current note", child.lua_get "delete_note_action.title")
  eq("obsidian.delete_note", child.lua_get "delete_note_action.command.command")
end

return T
