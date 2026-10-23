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

local function prepare_rename()
  return h.child_await(
    child,
    [[
      require("obsidian.lsp.handlers.prepare_rename")(nil, function(_, result)
        done(result and { placeholder = result.placeholder, range = result.range } or false)
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
  child.cmd "Obsidian rename new_target"
  h.child_wait_for_path(child, new_target_path)
  eq(true, new_target_path:exists())
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false) -- new_target
  eq(target_expected, table.concat(lines, "\n"))
end

T["rename current note does not insert frontmatter when disabled"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["plain.md"] = "hello\nworld",
  })

  local new_target_path = root / "renamed-plain.md"

  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["plain.md"])
  child.cmd "Obsidian rename renamed-plain"
  h.child_wait_for_path(child, new_target_path)
  eq(true, new_target_path:exists())
  local lines = child.api.nvim_buf_get_lines(1, 0, -1, false)
  eq("hello\nworld", table.concat(lines, "\n"))
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
  child.cmd "Obsidian rename target"
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
  child.cmd "Obsidian rename existing"
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
  child.cmd "Obsidian rename bad:name"
  h.child_wait(child, [[return _G.err_msg ~= nil]], { desc = "rename invalid filename message" })
  eq('Invalid filename "bad:name": contains forbidden character: ":"', child.lua_get "err_msg")
  eq(true, (root / target):exists())
  eq(false, (root / "bad:name.md"):exists())
end

T["rename current note allows same name in a different folder"] = function()
  local root = child.Obsidian.dir
  local folder = root / "other"
  folder:mkdir()
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    ["other/existing.md"] = "",
  })

  local new_target_path = root / "existing.md"

  child.cmd("edit " .. files[target])
  child.cmd "Obsidian rename existing"
  h.child_wait_for_path(child, new_target_path)
  eq(true, new_target_path:exists())
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
  eq("header", prepare_rename().placeholder)

  child.api.nvim_win_set_cursor(0, { 2, 13 })
  eq("block", prepare_rename().placeholder)
end

T["prepare rename answers per element under the cursor"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["P.md"] = table.concat({
      "plain text #tag", -- 1
      "## Old Title", -- 2
      "para ^blk-1", -- 3
      "text[^1]", -- 4
      "[[target]]", -- 5
    }, "\n"),
  })

  child.cmd("edit " .. files["P.md"])
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  eq(false, prepare_rename())
  child.api.nvim_win_set_cursor(0, { 1, 12 }) -- tags are not renameable yet
  eq(false, prepare_rename())

  child.api.nvim_win_set_cursor(0, { 2, 0 })
  eq("Old Title", prepare_rename().placeholder)

  child.api.nvim_win_set_cursor(0, { 3, 5 })
  local block = prepare_rename()
  eq("blk-1", block.placeholder)
  eq({ start = { line = 2, character = 6 }, ["end"] = { line = 2, character = 11 } }, block.range)

  child.api.nvim_win_set_cursor(0, { 4, 5 })
  eq("1", prepare_rename().placeholder)

  child.api.nvim_win_set_cursor(0, { 5, 3 })
  eq("target", prepare_rename().placeholder)
end

T["rename on plain text does nothing"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, { [target] = target_content })

  child.cmd("edit " .. files[target])
  child.api.nvim_win_set_cursor(0, { 6, 1 }) -- on "hello"

  rename "x"
  child.cmd "wa"

  eq(false, (root / "x.md"):exists())
  eq(target_content, table.concat(h.read(files[target]), "\n"))
end

local referencer2_expected = [==[
---
id: ref
aliases: []
tags: []
---

[[new_target#^block]]
]==]

T["rename note preserves matching wiki alias"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["index.md"] = [[---
id: index
aliases: []
tags: []
---]],
    [ref] = [==[

[[index|index]]
]==],
  })
  local new_target_path = root / "index-new.md"

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  rename "index-new"
  h.child_wait_for_path(child, new_target_path)
  child.cmd "wa"

  local ref_lines = h.read(files[ref])
  eq(true, table.concat(ref_lines, "\n"):find "%[%[index%-new|index%]%]" ~= nil)
end

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

T["Obsidian rename renames the current note even on a link"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    [target] = target_content,
    [ref] = ref_content,
  })

  child.cmd("edit " .. files[ref])
  child.api.nvim_win_set_cursor(0, { 2, 0 }) -- on [[target]]

  child.cmd "Obsidian rename ref-new"
  h.child_wait_for_path(child, root / "ref-new.md")
  eq(true, (root / "ref-new.md"):exists())
  eq(true, (root / target):exists())
end

T["rename on block id renames only the block id"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["A.md"] = "paragraph with id ^blk-1",
    ["B.md"] = "[[A#^blk-1]]",
  })

  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["A.md"])
  child.api.nvim_win_set_cursor(0, { 1, 18 })

  rename "novo-id"
  child.cmd "wa"

  eq({ "paragraph with id ^novo-id" }, h.read(files["A.md"]))
  eq({ "[[A#^novo-id]]" }, h.read(files["B.md"]))
  eq(false, (root / "novo-id.md"):exists())
end

T["rename block id rewrites definition and every reference"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["A.md"] = table.concat({
      "para ^blk-1",
      "",
      "see [[#^blk-1]] and [x](#^blk-1)",
      "```",
      "[[A#^blk-1]]",
      "```",
    }, "\n"),
    ["B.md"] = table.concat({
      "[[A#^blk-1]] ![[A#^blk-1]] [[A#^blk-1|alias]] [y](A.md#^blk-1) [[C#^blk-1]]",
      "`[[A#^blk-1]]`",
    }, "\n"),
  })

  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["A.md"])
  child.api.nvim_win_set_cursor(0, { 1, 5 })
  rename "novo-id"
  child.cmd "wa"

  eq({
    "para ^novo-id",
    "",
    "see [[#^novo-id]] and [x](#^novo-id)",
    "```",
    "[[A#^blk-1]]",
    "```",
  }, h.read(files["A.md"]))
  eq({
    "[[A#^novo-id]] ![[A#^novo-id]] [[A#^novo-id|alias]] [y](A.md#^novo-id) [[C#^blk-1]]",
    "`[[A#^blk-1]]`",
  }, h.read(files["B.md"]))
  eq(false, (root / "novo-id.md"):exists())
end

T["rename block id from a reference to it"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["A.md"] = "para ^blk-1\n\nsee [[#^blk-1]]",
  })

  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["A.md"])
  child.api.nvim_win_set_cursor(0, { 3, 6 })
  rename "other"
  child.cmd "wa"

  eq({ "para ^other", "", "see [[#^other]]" }, h.read(files["A.md"]))
end

T["rename block id rejects invalid and duplicate ids"] = function()
  local root = child.Obsidian.dir
  local content = "one ^a\n\ntwo ^b"
  local files = h.mock_vault_contents(root, { ["A.md"] = content })

  child.lua [[
require"obsidian.log".err = function(msg)
  _G.err_msg = msg
end
  ]]

  child.cmd("edit " .. files["A.md"])
  child.api.nvim_win_set_cursor(0, { 1, 5 })

  rename "bad id"
  eq('Invalid block id "bad id": use letters, digits and "-"', child.lua_get "err_msg")

  child.lua [[_G.err_msg = nil]]
  rename "b"
  eq('Block id "^b" already exists in this note', child.lua_get "err_msg")

  child.cmd "wa"
  eq(content, table.concat(h.read(files["A.md"]), "\n"))
end

T["rename block id edits a modified buffer of another note"] = function()
  local root = child.Obsidian.dir
  local files = h.mock_vault_contents(root, {
    ["A.md"] = "para ^blk-1",
    ["B.md"] = "[[A#^blk-1]]",
  })

  child.lua [[Obsidian.opts.frontmatter.enabled = false]]
  child.cmd("edit " .. files["B.md"])
  child.api.nvim_buf_set_lines(0, -1, -1, false, { "unsaved" })
  child.cmd("edit " .. files["A.md"])
  child.api.nvim_win_set_cursor(0, { 1, 5 })
  rename "novo-id"
  child.cmd "wa"

  eq({ "[[A#^novo-id]]", "unsaved" }, h.read(files["B.md"]))
end

return T
