local h = dofile "tests/helpers.lua"
local Note = require "obsidian.note"
local M = require "obsidian.daily"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["daily_note_path"] = h.temp_vault

T["daily_note_path"]["should use the path stem as the ID"] = function()
  Obsidian.opts.daily_notes.date_format = "%Y/%b/%Y-%m-%d"
  local path, id = M.daily_note_path(nil)
  assert(vim.endswith(tostring(path), tostring(os.date("%Y/%b/%Y-%m-%d.md", os.time()))))
  eq(id, os.date("%Y-%m-%d", os.time()))
end

T["daily_note_path"]["should be able to initialize a daily note"] = function()
  local note = M.today()
  eq(true, note.path ~= nil)
  eq(true, note:exists())
end

T["daily_note_path"]["should not add frontmatter for today when disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false
  local new_note = M.today()

  local saved_note = Note.from_file(new_note.path)
  eq(false, saved_note.has_frontmatter)
end

T["daily_note_path"]["should not add frontmatter for yesterday when disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false
  local new_note = M.yesterday()
  local saved_note = Note.from_file(new_note.path)
  eq(false, saved_note.has_frontmatter)
end

T["daily_note_path"]["should preserve date format in note ID without applying note_id_func"] = function()
  -- Set a custom note_id_func that would transform IDs (like zettel_id does)
  Obsidian.opts.note_id_func = function()
    return tostring(os.time()) .. "-TRANSFORMED"
  end
  Obsidian.opts.daily_notes.date_format = "%Y-%m-%d"
  
  local note = M.today()
  local expected_id = os.date("%Y-%m-%d", os.time())
  
  -- The note ID should match the date format, NOT be transformed by note_id_func
  eq(expected_id, note.id)
  
  -- The filename should use the date format
  eq(expected_id .. ".md", note.path.name)
  
  -- Ensure it doesn't contain "TRANSFORMED" (which would indicate note_id_func was applied)
  local has_transform = tostring(note.path):match("TRANSFORMED")
  eq(nil, has_transform)
end

return T
