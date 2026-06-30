local h = dofile "tests/helpers.lua"
local Note = require "obsidian.note"
local M = require "obsidian.daily"
local moment = require "obsidian.lib.moment"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["daily_note_path"] = h.temp_vault

T["daily_note_path"]["should use the path stem as the ID"] = function()
  Obsidian.opts.daily_notes.date_format = "%Y/%b/%Y-%m-%d"
  local path, id = M.daily_note_path(nil)
  assert(vim.endswith(tostring(path), tostring(os.date("%Y/%b/%Y-%m-%d.md", os.time()))))
  eq(id, os.date("%Y-%m-%d", os.time()))
end

T["daily_note_path"]["should support moment date_format"] = function()
  local previous = Obsidian.opts.daily_notes.date_format
  Obsidian.opts.daily_notes.date_format = "YYYY/MM/YYYY-MM-DD"

  local now = os.time()
  local path, id = M.daily_note_path(now)
  assert(vim.endswith(tostring(path), moment.format(now, "YYYY/MM/YYYY-MM-DD") .. ".md"))
  eq(id, moment.format(now, "YYYY-MM-DD"))

  Obsidian.opts.daily_notes.date_format = previous
end

T["daily_note_path"]["should be able to initialize a daily note"] = function()
  local note = M.today()
  eq(true, note.path ~= nil)
  note:write()
  eq(true, note:exists())
end

T["daily_note_path"]["should not add frontmatter for today when disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false
  local new_note = M.today()
  new_note:write()

  local saved_note = Note.from_file(new_note.path)
  eq(false, saved_note.has_frontmatter)
end

T["daily_note_path"]["should not add frontmatter for yesterday when disabled"] = function()
  Obsidian.opts.frontmatter.enabled = false
  local new_note = M.yesterday()
  new_note:write()
  local saved_note = Note.from_file(new_note.path)
  eq(false, saved_note.has_frontmatter)
end

T["dailies"] = h.temp_vault

T["dailies"]["don't be effected by `note_id_func`"] = function()
  local note = M.daily { offset = 0 }
  eq(note.id, os.date "%Y-%m-%d")
end

T["dailies"]["pick should use custom date resolver"] = function()
  local timestamp = os.time { year = 2026, month = 6, day = 25, hour = 12 }
  Obsidian.opts.resolvers.date = function(ctx, done)
    eq("open_daily", ctx.intent)
    eq("daily", ctx.cadence)
    done { timestamp = timestamp, precision = "day" }
  end

  local picked
  M.pick(-5, 0, function(note)
    picked = note
  end)

  eq("2026-06-25", picked.id)
end

return T
