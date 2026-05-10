local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local fs = require "obsidian.fs"
local exclusions = require "obsidian.exclusions"

local T = h.temp_vault

T["is_excluded with simple directory name"] = function()
  Obsidian.opts.ignore_filters = { "archive" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local ignore_dir = dir / "archive"
  local ignored_file = tostring(ignore_dir / "old_note.md")
  local kept_file = tostring(dir / "main_note.md")
  ignore_dir:mkdir()
  vim.fn.writefile({}, ignored_file)
  vim.fn.writefile({}, kept_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end

  eq(#result, 1)
  eq(result[1], kept_file)
end

T["is_excluded with glob pattern"] = function()
  Obsidian.opts.ignore_filters = { "private/**", "*.bak.md" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  vim.fn.mkdir(tostring(dir / "private" / "sub" / "deep"), "p")

  local ignored = tostring(dir / "private" / "secret.md")
  local ignored_deep = tostring(dir / "private" / "sub" / "deep" / "very_secret.md")
  local kept = tostring(dir / "main.md")
  local ignored_file = tostring(dir/"test.bak.md")
  vim.fn.writefile({}, ignored)
  vim.fn.writefile({}, ignored_deep)
  vim.fn.writefile({}, kept)
  vim.fn.writefile({}, ignored_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end

  eq(#result, 1)
  eq(result[1], kept)
end

T["is_excluded_dir correctly identifies directories"] = function()
  Obsidian.opts.ignore_filters = { "archive", "templates" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded_dir("archive"), true)
  eq(exclusions.is_excluded_dir("templates"), true)
  eq(exclusions.is_excluded_dir("notes"), false)
  eq(exclusions.is_excluded_dir(".obsidian"), false)
end

T["is_excluded works with vault relative paths"] = function()
  Obsidian.opts.ignore_filters = { "archive", "private" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded("archive/old.md"), true)
  eq(exclusions.is_excluded("private/secret.md"), true)
  eq(exclusions.is_excluded("notes/main.md"), false)
end

T["is_excluded works with absolute input paths"] = function()
  Obsidian.opts.ignore_filters = { "archive" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local archive_dir = dir / "archive"
  local notes_dir = dir / "notes"
  archive_dir:mkdir()
  notes_dir:mkdir()

  local archive_path = tostring(archive_dir / "old.md")
  local notes_path = tostring(notes_dir / "main.md")
  vim.fn.writefile({}, archive_path)
  vim.fn.writefile({}, notes_path)

  eq(exclusions.is_excluded(archive_path), true)
  eq(exclusions.is_excluded(notes_path), false)
end

T["no false positives with similar directory names"] = function()
  Obsidian.opts.ignore_filters = { "archive" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local archive_dir = dir / "archive"
  local archive_backup_dir = dir / "archive_backup"
  archive_dir:mkdir()
  archive_backup_dir:mkdir()

  local archive_file = tostring(archive_dir / "note.md")
  local backup_file = tostring(archive_backup_dir / "backup.md")
  vim.fn.writefile({}, archive_file)
  vim.fn.writefile({}, backup_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end

  -- archive should be excluded, archive_backup should NOT be
  eq(#result, 1)
  eq(result[1], backup_file)
end

T["clear_cache resets the checker"] = function()
  Obsidian.opts.ignore_filters = { "archive" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local new_dir = dir / "new_exclude"
  new_dir:mkdir()

  eq(type(exclusions._cache) == "table", true)
end

T["is_excluded with file-specific path"] = function()
  Obsidian.opts.ignore_filters = { "slides/present.md" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded_dir("slides"), false)
  eq(exclusions.is_excluded("slides/present.md"), true)
  eq(exclusions.is_excluded("slides/other.md"), false)
end

T["fs.dir with file-specific pattern does not prune directory"] = function()
  Obsidian.opts.ignore_filters = { "slides/present.md" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local slides_dir = dir / "slides"
  slides_dir:mkdir()

  local present_file = tostring(slides_dir / "present.md")
  local other_file = tostring(slides_dir / "other.md")
  local main_file = tostring(dir / "main.md")
  vim.fn.writefile({}, present_file)
  vim.fn.writefile({}, other_file)
  vim.fn.writefile({}, main_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end

  -- slides/ is entered (not pruned), but present.md is filtered out
  eq(#result, 2)
  eq(vim.tbl_contains(result, present_file), false)
  eq(vim.tbl_contains(result, other_file), true)
  eq(vim.tbl_contains(result, main_file), true)
end

T["is_excluded with root-anchored pattern only matches at root"] = function()
  Obsidian.opts.ignore_filters = { "/README.md" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded("README.md"), true)
  eq(exclusions.is_excluded("sub/README.md"), false)
  eq(exclusions.is_excluded_dir("sub"), false)
end

T["is_excluded with double-star pattern matches at any depth"] = function()
  Obsidian.opts.ignore_filters = { "**/draft.md" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded("draft.md"), true)
  eq(exclusions.is_excluded("notes/draft.md"), true)
  eq(exclusions.is_excluded("notes/sub/draft.md"), true)
end

T["is_excluded_dir with trailing slash pattern"] = function()
  Obsidian.opts.ignore_filters = { "archive/" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded_dir("archive"), true)
  eq(exclusions.is_excluded("archive/note.md"), true)
  eq(exclusions.is_excluded("other.md"), false)
  eq(exclusions.is_excluded_dir("other"), false)
end

T["fs.dir excludes directory with trailing slash pattern"] = function()
  Obsidian.opts.ignore_filters = { "archive/" }
  exclusions.clear_cache()

  local dir = Obsidian.dir
  local archive_dir = dir / "archive"
  archive_dir:mkdir()

  local ignored_file = tostring(archive_dir / "note.md")
  local kept_file = tostring(dir / "main.md")
  vim.fn.writefile({}, ignored_file)
  vim.fn.writefile({}, kept_file)

  local result = {}
  for path in fs.dir(dir) do
    result[#result + 1] = path
  end

  eq(#result, 1)
  eq(result[1], kept_file)
end

T["is_excluded with subdirectory wildcard pattern"] = function()
  Obsidian.opts.ignore_filters = { "drafts/*.md" }
  exclusions.clear_cache()

  eq(exclusions.is_excluded_dir("drafts"), false)
  eq(exclusions.is_excluded("drafts/foo.md"), true)
  eq(exclusions.is_excluded("drafts/sub/bar.md"), false)
end

return T
