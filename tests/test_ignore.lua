local eq = MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local fs = require "obsidian.fs"
local ignore = require "obsidian.ignore"

local T = h.temp_vault

T["is_ignored with simple directory name"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive" } }
  ignore.clear_cache()

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

T["is_ignored with glob pattern"] = function()
  Obsidian.opts.file = { ignore_filters = { "private/**", "*.bak.md" } }
  ignore.clear_cache()

  local dir = Obsidian.dir
  vim.fn.mkdir(tostring(dir / "private" / "sub" / "deep"), "p")

  local ignored = tostring(dir / "private" / "secret.md")
  local ignored_deep = tostring(dir / "private" / "sub" / "deep" / "very_secret.md")
  local kept = tostring(dir / "main.md")
  local ignored_file = tostring(dir / "test.bak.md")
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

T["is_ignored_dir correctly identifies directories"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive", "templates" } }
  ignore.clear_cache()

  eq(ignore.is_ignored_dir "archive", true)
  eq(ignore.is_ignored_dir "templates", true)
  eq(ignore.is_ignored_dir "notes", false)
  eq(ignore.is_ignored_dir ".obsidian", false)
end

T["is_ignored works with vault relative paths"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive", "private" } }
  ignore.clear_cache()

  eq(ignore.is_ignored "archive/old.md", true)
  eq(ignore.is_ignored "private/secret.md", true)
  eq(ignore.is_ignored "notes/main.md", false)
end

T["is_ignored works with absolute input paths"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive" } }
  ignore.clear_cache()

  local dir = Obsidian.dir
  local archive_dir = dir / "archive"
  local notes_dir = dir / "notes"
  archive_dir:mkdir()
  notes_dir:mkdir()

  local archive_path = tostring(archive_dir / "old.md")
  local notes_path = tostring(notes_dir / "main.md")
  vim.fn.writefile({}, archive_path)
  vim.fn.writefile({}, notes_path)

  eq(ignore.is_ignored(archive_path), true)
  eq(ignore.is_ignored(notes_path), false)
end

T["no false positives with similar directory names"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive" } }
  ignore.clear_cache()

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

  eq(#result, 1)
  eq(result[1], backup_file)
end

T["clear_cache resets the checker"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive" } }
  ignore.clear_cache()

  local dir = Obsidian.dir
  local new_dir = dir / "new_ignore"
  new_dir:mkdir()

  eq(type(ignore._cache) == "table", true)
end

T["is_ignored with file-specific path"] = function()
  Obsidian.opts.file = { ignore_filters = { "slides/present.md" } }
  ignore.clear_cache()

  eq(ignore.is_ignored_dir "slides", false)
  eq(ignore.is_ignored "slides/present.md", true)
  eq(ignore.is_ignored "slides/other.md", false)
end

T["fs.dir with file-specific pattern does not prune directory"] = function()
  Obsidian.opts.file = { ignore_filters = { "slides/present.md" } }
  ignore.clear_cache()

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

  eq(#result, 2)
  eq(vim.tbl_contains(result, present_file), false)
  eq(vim.tbl_contains(result, other_file), true)
  eq(vim.tbl_contains(result, main_file), true)
end

T["is_ignored with root-anchored pattern only matches at root"] = function()
  Obsidian.opts.file = { ignore_filters = { "/README.md" } }
  ignore.clear_cache()

  eq(ignore.is_ignored "README.md", true)
  eq(ignore.is_ignored "sub/README.md", false)
  eq(ignore.is_ignored_dir "sub", false)
end

T["is_ignored with double-star pattern matches at any depth"] = function()
  Obsidian.opts.file = { ignore_filters = { "**/draft.md" } }
  ignore.clear_cache()

  eq(ignore.is_ignored "draft.md", true)
  eq(ignore.is_ignored "notes/draft.md", true)
  eq(ignore.is_ignored "notes/sub/draft.md", true)
end

T["is_ignored_dir with trailing slash pattern"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive/" } }
  ignore.clear_cache()

  eq(ignore.is_ignored_dir "archive", true)
  eq(ignore.is_ignored "archive/note.md", true)
  eq(ignore.is_ignored "other.md", false)
  eq(ignore.is_ignored_dir "other", false)
end

T["fs.dir excludes directory with trailing slash pattern"] = function()
  Obsidian.opts.file = { ignore_filters = { "archive/" } }
  ignore.clear_cache()

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

T["is_ignored with subdirectory wildcard pattern"] = function()
  Obsidian.opts.file = { ignore_filters = { "drafts/*.md" } }
  ignore.clear_cache()

  eq(ignore.is_ignored_dir "drafts", false)
  eq(ignore.is_ignored "drafts/foo.md", true)
  eq(ignore.is_ignored "drafts/sub/bar.md", false)
end

return T
