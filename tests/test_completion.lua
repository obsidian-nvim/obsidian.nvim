local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["completion"] = new_set()

T["completion"]["refs"] = new_set()

T["completion"]["refs"]["can_complete should handle wiki links with text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "simple text [[foo"
  local request = {
    context = {
      cursor_before_line = before,
      cursor_after_line = "",
      cursor = {
        character = vim.fn.strchars(before),
      },
    },
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(12, insert_start)
  eq(17, insert_end)
end

T["completion"]["refs"]["can_complete should handle wiki links with preceding Unicode text"] = function()
  local completion = require "obsidian.completion.refs"

  local before = "Unicode text ű [[foo"
  local request = {
    context = {
      cursor_before_line = before,
      cursor_after_line = "",
      cursor = {
        character = vim.fn.strchars(before),
      },
    },
  }

  local can_complete, search, insert_start, insert_end, _ = completion.can_complete(request)
  eq(true, can_complete)
  eq("foo", search)
  eq(15, insert_start)
  eq(20, insert_end)
end

T["completion"]["refs"]["subdir path aliases"] = new_set {
  hooks = {
    pre_case = function()
      local Path = require "obsidian.path"
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        legacy_commands = false,
        workspaces = { { path = tostring(dir) } },
        completion = { blink = false, nvim_cmp = false },
        log_level = vim.log.levels.WARN,
      }

      local subdir = dir / "subdir"
      subdir:mkdir { parents = true }
      local nested_deep = dir / "nested" / "deep"
      nested_deep:mkdir { parents = true }

      local helpers = dofile "tests/helpers.lua"
      helpers.mock_vault_contents(dir, {
        ["foo.md"] = "---\n---\n\n# Foo Root\n",
        ["subdir/foo.md"] = "---\n---\n\n# Foo Subdir\n",
        ["subdir/bar.md"] = "---\naliases:\n  - mybar\n---\n\n# Bar\n",
        ["nested/deep/baz.md"] = "---\n---\n\n# Baz\n",
      })
    end,
    post_case = function()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

T["completion"]["refs"]["subdir path aliases"]["root note has no extra path alias"] = function()
  local Note = require "obsidian.note"
  local note = Note.from_file(tostring(Obsidian.dir / "foo.md"))
  local rel_path = note.path:vault_relative_path()
  local rel_stem = rel_path and rel_path:gsub("%.md$", "") or ""
  eq("foo", tostring(note.id))
  eq("foo", rel_stem)
end

T["completion"]["refs"]["subdir path aliases"]["subdir note gets relative path alias"] = function()
  local Note = require "obsidian.note"
  local note = Note.from_file(tostring(Obsidian.dir / "subdir" / "foo.md"))
  local rel_path = note.path:vault_relative_path()
  local rel_stem = rel_path and rel_path:gsub("%.md$", "") or ""
  eq("foo", tostring(note.id))
  eq("subdir/foo", rel_stem)
end

T["completion"]["refs"]["subdir path aliases"]["deeply nested note gets full relative path alias"] = function()
  local Note = require "obsidian.note"
  local note = Note.from_file(tostring(Obsidian.dir / "nested" / "deep" / "baz.md"))
  local rel_path = note.path:vault_relative_path()
  local rel_stem = rel_path and rel_path:gsub("%.md$", "") or ""
  eq("baz", tostring(note.id))
  eq("nested/deep/baz", rel_stem)
end

T["completion"]["refs"]["subdir path aliases"]["subdir note with aliases includes both name and path"] = function()
  local Note = require "obsidian.note"
  local util = require "obsidian.util"
  local note = Note.from_file(tostring(Obsidian.dir / "subdir" / "bar.md"))
  local aliases = util.tbl_unique { tostring(note.id), note:display_name(), unpack(note.aliases) }
  if note.path then
    local rel_path = note.path:vault_relative_path()
    if rel_path then
      local rel_stem = rel_path:gsub("%.md$", "")
      if rel_stem ~= tostring(note.id) then
        table.insert(aliases, rel_stem)
      end
    end
  end
  eq(true, vim.list_contains(aliases, "bar"))
  eq(true, vim.list_contains(aliases, "mybar"))
  eq(true, vim.list_contains(aliases, "subdir/bar"))
end

return T
