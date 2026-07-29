local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

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

return T
