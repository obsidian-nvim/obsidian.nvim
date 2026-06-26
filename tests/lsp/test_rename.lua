local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function rename(new_name)
  h.child_await(
    child,
    ([[
      require("obsidian.lsp.handlers.rename")({ newName = %q }, function(_, edit)
        if edit then
          vim.lsp.util.apply_workspace_edit(edit, "utf-8")
        end
        done(true)
      end)
    ]]):format(new_name),
    { desc = "rename" }
  )
end

local function prepare_rename_placeholder()
  return h.child_await(
    child,
    [[
      require("obsidian.lsp.handlers.prepare_rename")(nil, function(_, result)
        done(result.placeholder)
      end)
    ]],
    { desc = "prepare rename" }
  )
end

local target = "target.md"
local ref = "ref.md"

local target_content = [[---
id: target
aliases: []
tags: []
---
hello
world]]

local target_expected = [[---
id: new_target
aliases: []
tags: []
---
hello
world]]

local ref_content = [==[

[[target]]
]==]

T["rename current note"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
  })

  local new_target_path = root / "new_target.md"

  child.cmd("edit " .. files[target])
  rename "new_target"
  h.child_wait_for_path(child, new_target_path)
  eq(true, new_target_path:exists())
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq(target_expected, table.concat(lines, "\n"))
end

T["rename current note is no-op when name matches current note"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
  })

  child.lua [[
require"obsidian.log".info = function(msg)
   _G.msg = msg
end
  ]]

  child.cmd("edit " .. files[target])
  rename "target"
  h.child_wait(child, [[return _G.msg == "Identical name"]], { desc = "rename no-op message" })
  eq("Identical name", child.lua_get "msg")
end

T["rename current note is no-op when name matches an existing note"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    ["existing.md"] = "",
  })

  child.lua [[
require"obsidian.log".info = function(msg)
   _G.msg = msg
end
  ]]

  child.cmd("edit " .. files[target])
  rename "existing"
  h.child_wait(child, [[return _G.msg == "Note with same name exists"]], { desc = "rename no-op message" })
  eq("Note with same name exists", child.lua_get "msg")
end

T["rename rejects invalid filename"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
  })

  child.lua [[
require"obsidian.log".err = function(msg)
   _G.err_msg = msg
end
  ]]

  child.cmd("edit " .. files[target])
  rename "bad:name"
  h.child_wait(child, [[return _G.err_msg ~= nil]], { desc = "rename invalid filename message" })
  eq('Invalid filename "bad:name": contains forbidden character: ":"', child.lua_get "err_msg")
  eq(true, (root / target):exists())
  eq(false, (root / "bad:name.md"):exists())
end

T["rename note under cursor"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    [ref] = ref_content,
  })
  local new_target_path = (root / "new_target.md")

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  rename "new_target"
  h.child_wait_for_path(child, new_target_path)
  child.cmd "wa"
  eq(true, new_target_path:exists())
  local lines = vim.fn.readfile(tostring(new_target_path))

  eq(target_expected, table.concat(lines, "\n"))
end

T["prepare rename keeps fragment-only placeholders"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [ref] = [==[

[[#header]] [[#^block]]
]==],
  })

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  eq("#header", prepare_rename_placeholder())

  child.api.nvim_win_set_cursor(0, { 2, 13 })
  eq("#^block", prepare_rename_placeholder())
end

local referencer2_expected = [==[
---
id: ref
aliases: []
tags: []
---

[[new_target#^block]]
]==]

T["rename note without changing blocks and headers"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    [ref] = [==[

[[target#^block]]
]==],
  })
  local new_target_path = root / "new_target.md"

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  rename "new_target"
  h.child_wait_for_path(child, new_target_path)
  child.cmd "wa"
  eq(true, new_target_path:exists())

  local lines = h.read(new_target_path)
  local ref_lines = h.read(files[ref])
  eq(referencer2_expected, table.concat(ref_lines, "\n"))
  eq(target_expected, table.concat(lines, "\n"))
end

-- Test for issue #476: filenames with special Lua pattern characters
local special_target = "my-note.test.md"
local special_target_content = [[---
id: my-note.test
aliases: []
tags: []
---
hello
world]]

local special_target_expected = [[---
id: new-note
aliases: []
tags: []
---
hello
world]]

local special_ref_content = [==[

[[my-note.test]]
]==]

local special_ref_expected = [==[
---
id: ref
aliases: []
tags: []
---

[[new-note]]
]==]

T["rename note with special characters in filename"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    [special_target] = special_target_content,
    [ref] = special_ref_content,
  })
  local new_target_path = root / "new-note.md"

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  rename "new-note"
  h.child_wait_for_path(child, new_target_path)
  child.cmd "wa"
  eq(true, new_target_path:exists())

  local lines = h.read(new_target_path)
  local ref_lines = h.read(files[ref])
  eq(special_ref_expected, table.concat(ref_lines, "\n"))
  eq(special_target_expected, table.concat(lines, "\n"))
end

-- Test for issue #476: markdown links
local md_target_content = [[---
id: noteb
aliases: []
tags: []
---
# Note B

This is note B]]

local md_ref_content = [==[
---
id: notea
aliases: []
tags: []
---
# Note A

This is note A with a link to [Note B](noteb.md)
]==]

T["rename note with markdown link reference"] = function()
  local root = child.Obsidian.dir

  local files = h.mock_vault_contents(root, {
    ["noteb.md"] = md_target_content,
    ["notea.md"] = md_ref_content,
  })
  local new_target_path = root / "renamed-note.md"

  child.lua("vim.cmd.edit('" .. files["notea.md"]:gsub("'", "\\'") .. "')")
  child.api.nvim_win_set_cursor(0, { 8, 40 }) -- cursor on noteb.md in the link (line 8, col 40)

  rename "renamed-note"
  h.child_wait_for_path(child, new_target_path)
  child.cmd "wa"

  -- Check that file was renamed
  eq(true, new_target_path:exists())

  -- Check that link in referencing file was updated correctly
  local ref_lines = h.read(files["notea.md"])
  local md_ref_result = table.concat(ref_lines, "\n")
  eq(true, md_ref_result:find "%[Note B%]%(renamed%-note%.md%)" ~= nil, "Link should be updated to renamed-note.md")
end

return T
