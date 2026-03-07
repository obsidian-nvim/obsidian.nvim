local M = require "obsidian.actions"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local util = require "obsidian.util"
local Path = require "obsidian.path"

local T = h.temp_vault

T["create a unique note with timestamp"] = function()
  local timestamp = os.time()
  local note = M.new_unique_note(timestamp)
  local expected_id = util.format_date(timestamp, Obsidian.opts.unique_note.format)

  eq(expected_id, note.id)
  eq(true, note:exists())
end

T["create a unique note in specific folder"] = function()
  local previous = Obsidian.opts.unique_note.folder
  Obsidian.opts.unique_note.folder = "unique-notes"

  -- Create the folder
  Path.new(Obsidian.dir / "unique-notes"):mkdir()

  local note = M.new_unique_note()

  eq(true, tostring(note.path):find "unique%-notes" ~= nil)

  Obsidian.opts.unique_note.folder = previous
end

T["create a unique note with specific template"] = function()
  local previous = Obsidian.opts.unique_note.template
  Obsidian.opts.unique_note.template = "unique"

  -- Create template file
  h.write("# Unique Note Template\n{{title}}", Obsidian.dir / "templates" / "unique.md")

  local note = M.new_unique_note()
  local content = table.concat(h.read(note.path), "\n")

  eq(true, content:find "Unique Note Template" ~= nil)

  Obsidian.opts.unique_note.template = previous
end

T["use next available timestamp"] = function()
  -- Default format is "YYYYMMDDHHmm", smallest unit is minute
  local timestamp = os.time()
  local note1 = M.new_unique_note(timestamp)
  local note2 = M.new_unique_note(timestamp)

  -- note2 should be 1 minute after note1
  local expected_id = util.format_date(timestamp + 60, Obsidian.opts.unique_note.format)
  eq(expected_id, note2.id)
end

T["use next available timestamp for format with non numeric"] = function()
  local previous = Obsidian.opts.unique_note.format
  Obsidian.opts.unique_note.format = "YYYYMMDD-HHmmss"

  local timestamp = os.time()
  local note1 = M.new_unique_note(timestamp)
  local note2 = M.new_unique_note(timestamp)

  -- Smallest unit is second, note2 should be 1 second after note1
  local expected_id = util.format_date(timestamp + 1, "YYYYMMDD-HHmmss")
  eq(expected_id, note2.id)

  Obsidian.opts.unique_note.format = previous
end

T["create multiple unique notes in sequence"] = function()
  -- Default format "YYYYMMDDHHmm", increment by minutes
  local timestamp = os.time()
  local note1 = M.new_unique_note(timestamp)
  local note2 = M.new_unique_note(timestamp)
  local note3 = M.new_unique_note(timestamp)

  local expected_id1 = util.format_date(timestamp, Obsidian.opts.unique_note.format)
  local expected_id2 = util.format_date(timestamp + 60, Obsidian.opts.unique_note.format)
  local expected_id3 = util.format_date(timestamp + 120, Obsidian.opts.unique_note.format)

  eq(expected_id1, note1.id)
  eq(expected_id2, note2.id)
  eq(expected_id3, note3.id)
end

T["custom date format"] = function()
  local previous = Obsidian.opts.unique_note.format
  Obsidian.opts.unique_note.format = "YYYYMMDD"

  local timestamp = os.time()
  local note = M.new_unique_note(timestamp)
  local expected_id = util.format_date(timestamp, "YYYYMMDD")

  eq(expected_id, note.id)

  Obsidian.opts.unique_note.format = previous
end

return T
