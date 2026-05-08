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

T["strict resolve"] = new_set {
  hooks = {
    pre_case = function()
      child.lua [[
Obsidian.opts.link.resolve = "strict"
Obsidian.opts.notes_subdir = "notes"
Obsidian.opts.daily_notes.folder = "dailies"
local notes_dir = Obsidian.dir / "notes"
local dailies_dir = Obsidian.dir / "dailies"
local sub_dir = Obsidian.dir / "sub"
notes_dir:mkdir()
dailies_dir:mkdir()
sub_dir:mkdir()
vim.fn.writefile({ "---", "id: realid", "aliases: [\"My Alias\"]", "---", "# Foo" }, tostring(Obsidian.dir / "foo.md"))
vim.fn.writefile({ "# Sub Foo" }, tostring(sub_dir / "foo.md"))
vim.fn.writefile({ "# Bar" }, tostring(notes_dir / "bar.md"))
vim.fn.writefile({ "# Daily" }, tostring(dailies_dir / "daily.md"))
      ]]
    end,
  },
}

T["strict resolve"]["matches by basename across vault"] = function()
  local root = child.Obsidian.dir
  eq(tostring(root / "foo.md"), child.lua [[return M.resolve_link_path("foo")]])
  eq(tostring(root / "notes" / "bar.md"), child.lua [[return M.resolve_link_path("bar")]])
end

T["strict resolve"]["does not use notes_subdir or daily_notes magic"] = function()
  -- "daily" only exists under dailies/ — strict mode still finds via vault-wide basename match.
  local root = child.Obsidian.dir
  eq(tostring(root / "dailies" / "daily.md"), child.lua [[return M.resolve_link_path("daily")]])
end

T["strict resolve"]["does not match by alias"] = function()
  -- Obsidian app: aliases are autocomplete/display-only; [[alias]] does not navigate.
  eq(vim.NIL, child.lua [[return M.resolve_link_path("My Alias")]])
end

T["strict resolve"]["does not match by id"] = function()
  eq(vim.NIL, child.lua [[return M.resolve_link_path("realid")]])
end

T["strict resolve"]["resolves path-like links relative to current file"] = function()
  local root = child.Obsidian.dir
  child.lua(string.format([[vim.cmd("edit " .. vim.fn.fnameescape(%q))]], tostring(root / "sub" / "current.md")))
  eq(tostring(root / "sub" / "foo.md"), child.lua [[return M.resolve_link_path("foo")]])
end

T["strict resolve"]["resolves path-like links from vault root"] = function()
  local root = child.Obsidian.dir
  eq(tostring(root / "notes" / "bar.md"), child.lua [[return M.resolve_link_path("notes/bar")]])
  eq(tostring(root / "notes" / "bar.md"), child.lua [[return M.resolve_link_path("notes/bar.md")]])
end

T["strict resolve"]["returns nil for unknown link"] = function()
  eq(vim.NIL, child.lua [[return M.resolve_link_path("nonexistent")]])
end

return T
