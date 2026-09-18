local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local parser = require "obsidian.link.parser"

local T, child = h.child_vault {
  pre_case = [[M = require"obsidian.link"]],
}

T["includeexpr"] = new_set()

T["includeexpr"]["should resolve notes, files, folders, anchors, and urls for gf"] = function()
  local root = child.Obsidian.dir

  local note_path = tostring(root / "other.md")
  local file_path = tostring(root / "doc.txt")
  local folder_path = tostring(root / "docs")
  local linked_note_path = tostring(root / "notes" / "linked.md")
  local current_note_path = tostring(root / "current.md")

  child.lua(string.format(
    [=[
local docs_dir = Obsidian.dir / "docs"
local notes_dir = Obsidian.dir / "notes"
docs_dir:mkdir()
notes_dir:mkdir()
vim.fn.writefile({ "# Other" }, %q)
vim.fn.writefile({ "plain file" }, %q)
vim.fn.writefile({ "# Linked" }, %q)
vim.cmd("edit " .. vim.fn.fnameescape(%q))
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "[[notes/linked.md]]",
  "[doc](doc.txt)",
})
    ]=],
    note_path,
    file_path,
    linked_note_path,
    current_note_path
  ))

  eq(note_path, child.lua [[return M.resolve_link_path("other")]])
  eq(note_path, child.lua [[return M.resolve_link_path("other#heading")]])
  eq(file_path, child.lua [[return M.resolve_link_path("doc.txt")]])
  eq(folder_path, child.lua [[return M.resolve_link_path("docs")]])
  eq(vim.NIL, child.lua [[return M.resolve_link_path("https://example.com")]])

  child.api.nvim_win_set_cursor(0, { 1, 4 })
  eq(linked_note_path, child.lua [[return M.includeexpr("ignored.md")]])

  child.api.nvim_win_set_cursor(0, { 2, 6 })
  eq(file_path, child.lua [[return M.includeexpr("ignored.md")]])

  child.api.nvim_buf_set_lines(0, 2, 3, false, { "docs" })
  child.api.nvim_win_set_cursor(0, { 3, 1 })
  eq(folder_path, child.lua [[return M.includeexpr("docs")]])
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
