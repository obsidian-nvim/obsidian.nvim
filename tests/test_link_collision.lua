local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["plans only formerly unambiguous links whose target changes"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.mkdir(root .. "/other", "p")
vim.fn.writefile({ "old" }, root .. "/lib/entity.md")
vim.fn.writefile({ "new" }, root .. "/entity.md")
vim.fn.writefile({
  "---", "ref: '[[entity]]'", "---",
  "[[entity#Part|Label]] [Label](entity.md#Part) ![[entity]]",
  "`[[entity]]` [[/entity]]",
}, root .. "/other/source.md")
vim.fn.writefile({ "[[entity]]" }, root .. "/lib/source.md")
local plan = require("obsidian.link.collision").plan { new_path = root .. "/entity.md" }
local edits = plan.edits[root .. "/other/source.md"]
return { plan.count, plan.notes, #edits, plan.edits[root .. "/lib/source.md"] == nil,
  edits[1].newText, edits[2].newText, edits[3].newText, edits[4].newText }
  ]=]
  eq({ 4, 1, 4, true, "/lib/entity", "/lib/entity", "/lib/entity.md", "/lib/entity" }, result)
end

T["retains fragments and URI encoding in Markdown targets"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.writefile({ "old" }, root .. "/lib/my note.md")
vim.fn.writefile({ "new" }, root .. "/my note.md")
vim.fn.writefile({ "[Label](my%20note.md#Part)" }, root .. "/source.md")
Obsidian.opts.link.auto_update = true
local plan = require("obsidian.link.collision").plan { new_path = root .. "/my note.md" }
local applied = require("obsidian.link.collision_apply").apply(plan)
return { plan.count, applied, vim.fn.readfile(root .. "/source.md")[1] }
  ]=]
  eq({ 1, 1, "[Label](/lib/my%20note.md#Part)" }, result)
end

T["plans root-note repairs when a local note shadows it"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.writefile({ "root" }, root .. "/entity.md")
vim.fn.writefile({ "local" }, root .. "/lib/entity.md")
vim.fn.writefile({ "[[entity]]" }, root .. "/lib/source.md")
local plan = require("obsidian.link.collision").plan { new_path = root .. "/lib/entity.md" }
return { plan.count, plan.edits[root .. "/lib/source.md"][1].newText }
  ]=]
  eq({ 1, "/entity" }, result)
end

T["inspection shows target edits without applying them"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.writefile({ "old" }, root .. "/lib/entity.md")
vim.fn.writefile({ "new" }, root .. "/entity.md")
vim.fn.writefile({ "[[entity]]" }, root .. "/source.md")
local plan = require("obsidian.link.collision").plan { new_path = root .. "/entity.md" }
local calls = 0
require("obsidian.api").confirm = function()
  calls = calls + 1
  return calls == 1 and "Inspect" or "Yes"
end
local confirmed = require("obsidian.link.collision_apply").confirm(plan)
return { confirmed, calls, vim.fn.getqflist()[1].text, vim.fn.readfile(root .. "/source.md")[1] }
  ]=]
  eq({ true, 2, "entity → /lib/entity", "[[entity]]" }, result)
end

T["applies multiple edits per line and leaves open buffers unsaved"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.writefile({ "old" }, root .. "/lib/entity.md")
vim.fn.writefile({ "new" }, root .. "/entity.md")
local open_path = root .. "/open.md"
local closed_path = root .. "/closed.md"
vim.fn.writefile({ "[[entity]] and [one](entity.md)" }, open_path)
vim.fn.writefile({ "[[entity]]" }, closed_path)
vim.cmd("edit " .. vim.fn.fnameescape(open_path))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "[[entity]] and [one](entity.md) changed" })
Obsidian.opts.link.auto_update = true
local plan = require("obsidian.link.collision").plan { new_path = root .. "/entity.md" }
local applied, skipped = require("obsidian.link.collision_apply").apply(plan)
return { applied, skipped, vim.api.nvim_get_current_line(), vim.bo.modified,
  vim.fn.readfile(open_path)[1], vim.fn.readfile(closed_path)[1] }
  ]=]
  eq({
    3,
    0,
    "[[/lib/entity]] and [one](/lib/entity.md) changed",
    true,
    "[[entity]] and [one](entity.md)",
    "[[/lib/entity]]",
  }, result)
end

T["creating a colliding note repairs only old destinations"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["lib/entity.md"] = "old",
    ["other.md"] = "[[entity]] and [entity](entity.md)",
  })
  child.lua [[
Obsidian.opts.link.auto_update = true
local note = require("obsidian.note").create { id = "entity", dir = Obsidian.dir, verbatim = true }
note:write()
  ]]
  h.child_wait(
    child,
    ([=[return vim.fn.readfile(%q)[1] == "[[/lib/entity]] and [entity](/lib/entity.md)"]=]):format(root .. "/other.md"),
    {
      desc = "old links repaired after creation",
    }
  )
  eq("[[/lib/entity]] and [entity](/lib/entity.md)", vim.fn.readfile(root .. "/other.md")[1])
end

T["templated creation repairs after the final write"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["lib/entity.md"] = "old",
    ["source.md"] = "[[entity]]",
    ["templates/simple.md"] = "# Template",
  })
  child.lua [[
Obsidian.opts.link.auto_update = true
local note = require("obsidian.note").create { id = "entity", dir = Obsidian.dir, verbatim = true,
  template = "simple" }
note:write()
  ]]
  h.child_wait(child, ([=[return vim.fn.readfile(%q)[1] == "[[/lib/entity]]"]=]):format(root .. "/source.md"), {
    desc = "templated collision repair",
  })
  eq(true, vim.uv.fs_stat(root .. "/entity.md") ~= nil)
end

T["renaming into a colliding stem preserves existing links"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["lib/entity.md"] = "old",
    ["other/renamed.md"] = "original target",
    ["lib/source.md"] = "[[renamed]] [[entity]]",
  })
  child.lua [[
Obsidian.opts.link.auto_update = true
require("obsidian.note").from_file(tostring(Obsidian.dir / "lib/entity.md")):rename("renamed")
  ]]
  h.child_wait(
    child,
    ([=[return vim.fn.readfile(%q)[1] == "[[/other/renamed]] [[renamed]]"]=]):format(root .. "/lib/source.md"),
    {
      desc = "rename collision repairs",
    }
  )
  eq(true, vim.uv.fs_stat(root .. "/lib/renamed.md") ~= nil)
  eq(false, vim.uv.fs_stat(root .. "/lib/entity.md") ~= nil)
end

T["rename updates only short links that resolve to the renamed duplicate"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["entity.md"] = "root target",
    ["lib/entity.md"] = "renamed target",
    ["source.md"] = "[[entity]]",
    ["lib/source.md"] = "[[entity]]",
  })
  child.lua [[
Obsidian.opts.link.auto_update = true
require("obsidian.note").from_file(tostring(Obsidian.dir / "lib/entity.md")):rename("renamed")
  ]]
  h.child_wait_for_path(child, root .. "/lib/renamed.md")
  h.child_wait(child, ([=[return vim.fn.readfile(%q)[1] == "[[renamed]]"]=]):format(root .. "/lib/source.md"), {
    desc = "resolved duplicate link renamed",
  })
  eq("[[entity]]", vim.fn.readfile(root .. "/source.md")[1])
end

T["declining creation repair leaves old links and the new file"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["lib/entity.md"] = "old",
    ["source.md"] = "[[entity]]",
  })
  child.lua [[
local api = require "obsidian.api"
Obsidian.opts.link.auto_update = false
api.confirm = function() return "No" end
local note = require("obsidian.note").create { id = "entity", dir = Obsidian.dir, verbatim = true }
note:write()
  ]]
  h.child_wait_for_path(child, root .. "/entity.md")
  eq("[[entity]]", vim.fn.readfile(root .. "/source.md")[1])
end

T["declining rename repair cancels the whole rename"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["lib/entity.md"] = "old",
    ["other/renamed.md"] = "original target",
    ["lib/source.md"] = "[[renamed]]",
  })
  child.lua [[
Obsidian.opts.link.auto_update = false
require("obsidian.api").confirm = function() return "No" end
require("obsidian.note").from_file(tostring(Obsidian.dir / "lib/entity.md")):rename("renamed", nil, function(err)
  _G.rename_cancelled = err == "Aborted"
end)
  ]]
  h.child_wait(child, [[return _G.rename_cancelled == true]], { desc = "rename declined" })
  eq(true, vim.uv.fs_stat(root .. "/lib/entity.md") ~= nil)
  eq(false, vim.uv.fs_stat(root .. "/lib/renamed.md") ~= nil)
  eq("[[renamed]]", vim.fn.readfile(root .. "/lib/source.md")[1])
end

T["rename does not write unrelated dirty buffers"] = function()
  local root = tostring(child.Obsidian.dir)
  h.mock_vault_contents(child.Obsidian.dir, {
    ["entity.md"] = "target",
    ["unrelated.md"] = "on disk",
  })
  child.cmd("edit " .. vim.fn.fnameescape(root .. "/unrelated.md"))
  child.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
  child.lua [[
require("obsidian.note").from_file(tostring(Obsidian.dir / "entity.md")):rename("renamed")
  ]]
  h.child_wait_for_path(child, root .. "/renamed.md")
  h.child_wait(child, [[return not vim.uv.fs_stat(tostring(Obsidian.dir / "entity.md"))]], {
    desc = "old note removed",
  })
  eq("unsaved", child.api.nvim_get_current_line())
  eq(true, child.lua_get [[vim.bo.modified]])
  eq("on disk", vim.fn.readfile(root .. "/unrelated.md")[1])
end

return T
