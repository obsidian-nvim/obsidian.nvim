local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local parser = require "obsidian.link.parser"

local T, child = h.child_vault {
  pre_case = [[M = require"obsidian.link"]],
}

T["replace and unlink edit an explicit buffer range"] = function()
  local result = child.lua [=[
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(buf, tostring(Obsidian.dir / "source.md"))
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "See target now" })
local Range = require "obsidian.range"
M.replace { bufnr = buf, range = Range.new(0, 4, 0, 10), text = "[[target|Target]]" }
local linked = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
local ref = require("obsidian.parse.refs").extract(linked, { row = 0 })[1]
local display = M.unlink { bufnr = buf, ref = ref }
return { linked, display, vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] }
  ]=]
  eq({ "See [[target|Target]] now", "Target", "See Target now" }, result)
end

T["insert adds link text at an explicit position"] = function()
  local line = child.lua [=[
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "See  now" })
require("obsidian.link").insert {
  bufnr = buf,
  pos = require("obsidian.pos").new(0, 4),
  text = "[[target]]",
}
return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
  ]=]
  eq("See [[target]] now", line)
end

T["explicit root paths resolve independently of a neighboring note"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/nested", "p")
vim.fn.writefile({ "root" }, root .. "/entity.md")
vim.fn.writefile({ "local" }, root .. "/nested/entity.md")
local source = root .. "/nested/source.md"
vim.fn.writefile({ "[[/entity]] [root](/entity.md)" }, source)
local Link = require "obsidian.link"
local search = require "obsidian.search"
local api = require "obsidian.api"
local resolved = search.resolve_note("/entity", { dir = api.resolve_workspace_dir(source), buf_dir = root .. "/nested" })
return {
  Link.resolve_link_path("entity", source),
  Link.resolve_link_path("/entity", source),
  Link.resolve_link_path("/entity.md", source),
  tostring(resolved[1].path),
}
  ]=]
  local root = tostring(child.Obsidian.dir)
  eq({ root .. "/nested/entity.md", root .. "/entity.md", root .. "/entity.md", root .. "/entity.md" }, result)
end

T["render uses a rooted path for colliding stems"] = function()
  local result = child.lua [=[
local root = tostring(Obsidian.dir)
vim.fn.mkdir(root .. "/lib", "p")
vim.fn.writefile({ "old" }, root .. "/lib/entity.md")
vim.fn.writefile({ "new" }, root .. "/entity.md")
local Note = require "obsidian.note"
local Link = require "obsidian.link"
local opts = { label = "entity", source_path = root .. "/other.md" }
local old = Link.render(Note.from_file(root .. "/lib/entity.md"), opts)
local new = Link.render(Note.from_file(root .. "/entity.md"), opts)
local explicit_shortest = Link.render(Note.from_file(root .. "/entity.md"), vim.tbl_extend("force", opts, {
  format = "shortest",
}))
Obsidian.opts.link.style = "markdown"
local markdown = Link.render(Note.from_file(root .. "/entity.md"), opts)
return { old, new, explicit_shortest, markdown }
  ]=]
  eq({ "[[/lib/entity|entity]]", "[[/entity|entity]]", "[[/entity|entity]]", "[entity](/entity.md)" }, result)
end

T["includeexpr"] = new_set()

T["includeexpr"]["should resolve notes, anchors, and urls for gf"] = function()
  local root = child.Obsidian.dir

  local note_path = tostring(root / "other.md")
  local linked_note_path = tostring(root / "notes" / "linked.md")
  local current_note_path = tostring(root / "current.md")

  child.lua(string.format(
    [=[
local notes_dir = Obsidian.dir / "notes"
notes_dir:mkdir()
vim.fn.writefile({ "# Other" }, %q)
vim.fn.writefile({ "# Linked" }, %q)
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "[[notes/linked.md]]",
  "[linked](notes/linked.md)",
})
    ]=],
    note_path,
    linked_note_path,
    current_note_path
  ))

  eq(note_path, child.lua [[return M.resolve_link_path("other")]])
  eq(note_path, child.lua [[return M.resolve_link_path("other#heading")]])
  eq(vim.NIL, child.lua [[return M.resolve_link_path("https://example.com")]])

  child.api.nvim_win_set_cursor(0, { 1, 4 })
  eq(linked_note_path, child.lua [[return M.includeexpr("ignored.md")]])

  child.api.nvim_win_set_cursor(0, { 2, 6 })
  eq(linked_note_path, child.lua [[return M.includeexpr("ignored.md")]])
end

T["includeexpr"]["prefers a source-directory note over a vault duplicate"] = function()
  local root = child.Obsidian.dir
  local nested_dir = root / "nested"
  nested_dir:mkdir()

  local source_path = nested_dir / "current.md"
  local source_target = nested_dir / "target.md"
  local vault_target = root / "target.md"
  vim.fn.writefile({ "# Source" }, tostring(source_target))
  vim.fn.writefile({ "# Vault" }, tostring(vault_target))
  vim.fn.writefile({ "# Current" }, tostring(source_path))
  child.cmd("edit " .. vim.fn.fnameescape(tostring(source_path)))

  eq(tostring(source_target), child.lua [[return M.resolve_link_path("target")]])
end

T["parse"] = new_set()

T["parse"]["splits anchors and blocks"] = function()
  local location, anchor, block = parser.parse "dir/note#Heading"
  eq("dir/note", location)
  eq("Heading", anchor)
  eq(nil, block)

  location, anchor, block = parser.parse "dir/note#^block-id"
  eq("dir/note", location)
  eq(nil, anchor)
  eq("block-id", block)

  location, anchor, block = parser.parse "#Parent#Child"
  eq("", location)
  eq("Parent#Child", anchor)
  eq(nil, block)
end

T["parse"]["preserves incomplete fragments"] = function()
  local location, anchor, block = parser.parse "note#"
  eq("note", location)
  eq("", anchor)
  eq(nil, block)

  location, anchor, block = parser.parse "note#^"
  eq("note", location)
  eq(nil, anchor)
  eq("", block)
end

T["parse"]["formats canonical fragments"] = function()
  eq("note#Heading", parser.format("note", "#Heading"))
  eq("note#^block", parser.format("note", nil, "#^block"))
end

T["parse"]["does not split URI fragments or Windows paths"] = function()
  local location, anchor, block = parser.parse "https://example.com/page#fragment"
  eq("https://example.com/page#fragment", location)
  eq(nil, anchor)
  eq(nil, block)

  location, anchor, block = parser.parse [[C:\notes\note]]
  eq([[C:\notes\note]], location)
  eq(nil, anchor)
  eq(nil, block)
end

T["missing_link_path predicts paths without firing creation hooks"] = function()
  local result = child.lua [[
local callback_calls = 0
local autocmd_calls = 0
Obsidian.opts.callbacks.create_note = function()
  callback_calls = callback_calls + 1
end
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteCreate",
  callback = function()
    autocmd_calls = autocmd_calls + 1
  end,
})

local note_path = M.missing_link_path("Missing")
local attachment_path = M.missing_link_path("PHOTO.PNG", tostring(Obsidian.dir / "Current.md"))
return {
  callback_calls = callback_calls,
  autocmd_calls = autocmd_calls,
  note_path = note_path,
  attachment_path = attachment_path,
}
  ]]

  eq(0, result.callback_calls)
  eq(0, result.autocmd_calls)
  eq(true, vim.endswith(result.note_path, ".md"))
  eq(true, vim.endswith(result.attachment_path, "PHOTO.PNG"))
end

T["missing_link_path preserves relative and vault-absolute semantics"] = function()
  local result = child.lua [[
Obsidian.opts.note_id_func = function(id)
  return id
end
local source = tostring(Obsidian.dir / "nested" / "Current.md")
local api = require "obsidian.api"
local original_confirm = api.confirm
api.confirm = function()
  return "Yes"
end
api.create_new_note("./Created", nil, { source_path = source })
api.create_new_note("../Root", nil, { source_path = source })
api.create_new_note("/Absolute", nil, { source_path = source })
api.confirm = original_confirm
return {
  sibling = M.missing_link_path("./Sibling", source),
  parent = M.missing_link_path("../Parent", source),
  absolute = M.missing_link_path("/AbsoluteMissing", source),
  attachment = M.missing_link_path("/assets/Image.png", source),
  created_sibling = vim.uv.fs_stat(tostring(Obsidian.dir / "nested" / "Created.md")) ~= nil,
  created_parent = vim.uv.fs_stat(tostring(Obsidian.dir / "Root.md")) ~= nil,
  created_absolute = vim.uv.fs_stat(tostring(Obsidian.dir / "Absolute.md")) ~= nil,
}
  ]]

  eq(tostring(child.Obsidian.dir / "nested" / "Sibling.md"), result.sibling)
  eq(tostring(child.Obsidian.dir / "Parent.md"), result.parent)
  eq(tostring(child.Obsidian.dir / "AbsoluteMissing.md"), result.absolute)
  eq(tostring(child.Obsidian.dir / "assets" / "Image.png"), result.attachment)
  eq(true, result.created_sibling)
  eq(true, result.created_parent)
  eq(true, result.created_absolute)
end

return T
