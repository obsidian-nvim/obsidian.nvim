local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[M = require"obsidian.link"]],
}

T["includeexpr"] = new_set()
T["resolver"] = new_set()

T["resolver"]["classifies normalized targets"] = function()
  local result = child.lua [[
return {
  external = M.parse_target("https://example.com/a").kind,
  attachment = M.parse_target(".\\PHOTO.PNG").kind,
  local_kind = M.parse_target("#Heading").kind,
  local_anchor = M.parse_target("#Heading").anchor,
  note = M.parse_target("Folder%2FNote#Section").normalized,
}
  ]]

  eq("external", result.external)
  eq("attachment", result.attachment)
  eq("local_fragment", result.local_kind)
  eq("#heading", result.local_anchor)
  eq("Folder/Note", result.note)
end

T["resolver"]["uses exact identifiers and reports ambiguity"] = function()
  local result = child.lua [[
vim.fn.writefile({ "---", "aliases: [Shared]", "---" }, tostring(Obsidian.dir / "One.md"))
vim.fn.writefile({ "---", "aliases: [Shared]", "---" }, tostring(Obsidian.dir / "Two.md"))
vim.fn.writefile({ "# Foobar" }, tostring(Obsidian.dir / "Foobar.md"))
local shared = M.resolve("shared")
local fuzzy = M.resolve("Foo")
return {
  shared_status = shared.status,
  shared_paths = shared.paths,
  fuzzy_status = fuzzy.status,
}
  ]]

  eq("ambiguous", result.shared_status)
  eq(2, #result.shared_paths)
  eq("missing", result.fuzzy_status)
end

T["resolver"]["uses explicit source paths and predicts without creation hooks"] = function()
  local result = child.lua [[
local sub = Obsidian.dir / "sub"
sub:mkdir()
local source = tostring(sub / "Current.md")
local target = tostring(sub / "Target.md")
vim.fn.writefile({ "" }, source)
vim.fn.writefile({ "" }, target)
vim.fn.writefile({ "root" }, tostring(Obsidian.dir / "Root.md"))
vim.fn.writefile({ "nested" }, tostring(sub / "Root.md"))
local callback_calls = 0
local autocmd_calls = 0
Obsidian.opts.note_id_func = function(title)
  return title
end
Obsidian.opts.callbacks.create_note = function()
  callback_calls = callback_calls + 1
end
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianNoteCreate",
  callback = function()
    autocmd_calls = autocmd_calls + 1
  end,
})
local resolved = M.resolve("./Target", { source_path = source })
local rooted = M.resolve("/Root", { source_path = source })
local predicted = M.missing_link_path("Missing", source)
local rooted_prediction = M.missing_link_path("/Missing", source)
local escaped = M.missing_link_path("../../Outside", source)
return {
  resolved = resolved.path,
  status = resolved.status,
  rooted = rooted.path,
  predicted = predicted,
  rooted_prediction = rooted_prediction,
  escaped = escaped,
  callback_calls = callback_calls,
  autocmd_calls = autocmd_calls,
}
  ]]

  eq("resolved", result.status)
  eq(tostring(child.Obsidian.dir / "sub" / "Target.md"), result.resolved)
  eq(tostring(child.Obsidian.dir / "Root.md"), result.rooted)
  eq(true, vim.endswith(result.predicted, "Missing.md"))
  eq(tostring(child.Obsidian.dir / "Missing.md"), result.rooted_prediction)
  eq(nil, result.escaped)
  eq(0, result.callback_calls)
  eq(0, result.autocmd_calls)
end

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

return T
