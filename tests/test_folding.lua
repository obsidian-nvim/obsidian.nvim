local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local note = [[---
fold_startup: contents
---
Introductory prose
# One
one body
### Child
child body
#### Grandchild
grandchild body
### Bare
# Two
```
# not a heading
```
# Three
three body]]

local function open_note(text)
  local files = h.child_mock_vault_contents(child, { ["folds.md"] = text or note })
  child.cmd("edit " .. vim.fn.fnameescape(files["folds.md"]))
  child.lua [[
    Folding = require "obsidian.folding"
    Actions = require "obsidian.actions"
    Folding.enable()
    FoldEnds = function(...)
      return vim.tbl_map(vim.fn.foldclosedend, { ... })
    end
  ]]
end

T["global cycles through roots, all headings, and all text"] = function()
  open_note()
  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 10, 2 })
    Actions.fold_cycle_global()
  ]]
  eq({ 3, -1, 11, 11, 11, 11, 15, 17 }, child.lua_get [[FoldEnds(1, 4, 5, 7, 9, 11, 12, 16)]])
  eq({ 5, 0 }, child.lua_get [[vim.api.nvim_win_get_cursor(0)]])
  eq("Properties", child.lua_get [[vim.fn.foldtextresult(1)]])

  child.lua [[Actions.fold_cycle_global()]]
  eq({ 3, -1, 6, 8, 10, -1, 15, 17 }, child.lua_get [[FoldEnds(1, 4, 5, 7, 9, 11, 12, 16)]])

  child.lua [[Actions.fold_cycle_global()]]
  eq({ -1, -1, -1, -1, -1, -1, -1, -1 }, child.lua_get [[FoldEnds(1, 4, 5, 7, 9, 11, 12, 16)]])
end

T["local cycles leave folds outside the subtree alone"] = function()
  open_note()
  child.lua [[
    Folding.set_global("show_all")
    vim.cmd("12foldclose")
    vim.api.nvim_win_set_cursor(0, { 5, 2 })
    Actions.fold_cycle()
  ]]
  eq({ 11, 11, 11, 11, 15 }, child.lua_get [[FoldEnds(5, 7, 9, 11, 12)]])
  eq({ 5, 2 }, child.lua_get [[vim.api.nvim_win_get_cursor(0)]])

  child.lua [[Actions.fold_cycle()]]
  eq({ -1, -1, 10, 10, -1, 15 }, child.lua_get [[FoldEnds(5, 6, 7, 9, 11, 12)]])

  child.lua [[Actions.fold_cycle()]]
  eq({ -1, -1, -1, -1, 15 }, child.lua_get [[FoldEnds(5, 7, 9, 11, 12)]])
end

T["local cycling from contents does not change the global cycle"] = function()
  open_note()
  child.lua [[
    Folding.set_global("contents")
    vim.api.nvim_win_set_cursor(0, { 7, 0 })
    Actions.fold_cycle()
  ]]
  eq({ 6, 10, 10, 15 }, child.lua_get [[FoldEnds(5, 7, 9, 12)]])
  child.lua [[Actions.fold_cycle()]]
  eq({ 6, -1, 10, 15 }, child.lua_get [[FoldEnds(5, 7, 9, 12)]])
  child.lua [[Actions.fold_cycle()]]
  eq({ 6, -1, -1, 15 }, child.lua_get [[FoldEnds(5, 7, 9, 12)]])
  child.lua [[Actions.fold_cycle_global()]]
  eq({ -1, -1, -1, -1 }, child.lua_get [[FoldEnds(5, 7, 9, 12)]])
end

T["local cycling toggles Properties without changing heading folds"] = function()
  open_note()
  child.lua [[
    Folding.set_global("contents")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    Actions.fold_cycle()
  ]]
  eq({ -1, 6, 8 }, child.lua_get [[FoldEnds(1, 5, 7)]])

  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    Actions.fold_cycle()
  ]]
  eq({ 3, 6, 8 }, child.lua_get [[FoldEnds(1, 5, 7)]])
  eq({ 1, 0 }, child.lua_get [[vim.api.nvim_win_get_cursor(0)]])
end

T["leaves have two states and off-heading actions do nothing"] = function()
  open_note()
  child.lua [[
    Folding.set_global("show_all")
    for _, line in ipairs({ 4, 6, 11, 14 }) do
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      Actions.fold_cycle()
    end
  ]]
  eq({ -1, -1, -1 }, child.lua_get [[FoldEnds(1, 5, 12)]])

  child.lua [[
    vim.api.nvim_win_set_cursor(0, { 16, 0 })
    Actions.fold_cycle()
  ]]
  eq({ 17 }, child.lua_get [[FoldEnds(16)]])
  child.lua [[Actions.fold_cycle()]]
  eq({ -1 }, child.lua_get [[FoldEnds(16)]])
end

T["setext underlines can target a subtree but a bare heading does not fold"] = function()
  open_note [[Title
=====
body
Subtitle
--------
child body
# Peer
Bare
----]]
  child.lua [[
    Folding.set_global("contents")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
  ]]
  eq({ 3, 6, -1, -1 }, child.lua_get [[FoldEnds(1, 4, 8, 9)]])
  child.lua [[Actions.fold_cycle()]]
  eq({ 6, 6, -1, -1 }, child.lua_get [[FoldEnds(1, 4, 8, 9)]])
  eq({ 1, 0 }, child.lua_get [[vim.api.nvim_win_get_cursor(0)]])
end

T["local cycling uses the outline after a heading edit"] = function()
  open_note [[### Root
body
#### Child
child body
# Peer
peer body]]
  child.lua [[
    Folding.set_global("overview")
  ]]
  eq({ 4, 4, 6 }, child.lua_get [[FoldEnds(1, 3, 5)]])

  child.lua [[
    Folding.set_global("show_all")
    vim.api.nvim_buf_set_lines(0, 2, 3, false, { "### Now a root" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    Actions.fold_cycle()
  ]]
  eq({ 2, -1, -1 }, child.lua_get [[FoldEnds(1, 3, 5)]])
end

T["global fold state belongs to a window and buffer"] = function()
  open_note()
  child.lua [[
    Folding.set_global("contents")
    FirstWindow = vim.api.nvim_get_current_win()
    FirstBuffer = vim.api.nvim_get_current_buf()
    vim.cmd("vsplit")
    Actions.fold_cycle_global()
  ]]
  eq({ 11 }, child.lua_get [[FoldEnds(5)]])
  child.lua [[vim.api.nvim_set_current_win(FirstWindow)]]
  eq({ 6 }, child.lua_get [[FoldEnds(5)]])

  child.lua [[
    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# Temporary", "body" })
    Folding.enable()
    Actions.fold_cycle_global()
  ]]
  eq({ 2 }, child.lua_get [[FoldEnds(1)]])
  child.lua [[
    vim.api.nvim_set_current_buf(FirstBuffer)
    Actions.fold_cycle_global()
  ]]
  eq({ -1 }, child.lua_get [[FoldEnds(5)]])
end

T["enabling folding does not change other buffers' fold options"] = function()
  open_note()
  local options = child.lua [[
    vim.wo.foldmethod = "indent"
    vim.wo.foldtext = ""
    Folding.enable()
    Folding.set_global("contents")
    vim.cmd("enew")
    return { vim.wo.foldmethod, vim.wo.foldtext }
  ]]
  eq({ "indent", "" }, options)
end

T["actions leave other folding sources alone"] = function()
  open_note()
  eq(
    { "expr", "0", false },
    child.lua [[
    vim.wo.foldexpr = "0"
    Actions.fold_cycle()
    Actions.fold_cycle_global()
    return { vim.wo.foldmethod, vim.wo.foldexpr, Folding.set_global("contents") }
  ]]
  )
end

return T
