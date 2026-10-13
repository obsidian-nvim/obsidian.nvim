local h = dofile "tests/helpers.lua"
local daily = require "obsidian.daily"
local resolvers = require "obsidian.resolvers"
local commands = require "obsidian.commands"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()
T["daily commands"] = h.temp_vault

local function run(name, ...)
  local fargs = { name, ... }
  commands.handle_command { fargs = fargs, range = 0 }
end

local function wait_for_note(id)
  h.wait(function()
    return vim.fn.expand "%:t:r" == id
  end, { desc = "daily note " .. id })
end

T["daily commands"]["bare daily opens today without invoking the parse resolver"] = function()
  Obsidian.opts.resolvers.date_parse = function()
    error "bare daily must not parse"
  end
  run "daily"
  local note = daily.today()
  eq(true, note:exists())
  wait_for_note(note.id)
  eq(tostring(note.path), vim.api.nvim_buf_get_name(0))
end

T["daily commands"]["default parser handles calendar offsets, formatted dates, and working days"] = function()
  local function parse(input)
    local result, err
    resolvers.resolve("date_parse", { input = input, intent = "open_daily" }, function(value, failure)
      result, err = value, failure
    end)
    assert(result, input .. ": " .. tostring(err))
    return result.timestamp
  end

  eq(daily.daily({ offset = 1 }).id, daily.daily({ date = parse "+1" }).id)
  eq("2026-06-25", daily.daily({ date = parse "2026-06-25" }).id)
  eq(daily.tomorrow().id, daily.daily({ date = parse "tomorrow" }).id)
  eq(daily.yesterday().id, daily.daily({ date = parse "yesterday" }).id)
  Obsidian.opts.daily_notes.workdays_only = false
  eq(daily.daily({ offset = 1 }).id, daily.daily({ date = parse "tomorrow" }).id)
end

T["daily commands"]["named days skip weekends but numeric offsets do not"] = function()
  local actual_time = os.time
  local now = actual_time { year = 2026, month = 1, day = 2, hour = 12 } -- Friday
  local function parse(input)
    local result
    resolvers.resolve("date_parse", { input = input, intent = "open_daily" }, function(value)
      result = value
    end)
    return os.date("%Y-%m-%d", result.timestamp)
  end

  local ok, err = pcall(function()
    rawset(os, "time", function(value)
      return value and actual_time(value) or now
    end)
    eq("2026-01-05", parse "tomorrow")
    eq("2026-01-03", parse "+1")
    Obsidian.opts.daily_notes.workdays_only = false
    eq("2026-01-03", parse "tomorrow")
    Obsidian.opts.daily_notes.workdays_only = true
    now = actual_time { year = 2026, month = 1, day = 5, hour = 12 } -- Monday
    eq("2026-01-02", parse "yesterday")
    eq("2026-01-04", parse "-1")
  end)
  rawset(os, "time", actual_time)
  if not ok then
    error(err)
  end
end

T["daily commands"]["custom parser receives full expressions and can use the built-in fallback"] = function()
  local seen = {}
  Obsidian.opts.resolvers.date_parse = function(ctx, done)
    eq(resolvers.builtin.date_parse, ctx.fallback)
    seen[#seen + 1] = ctx.input
    if ctx.input == "next review" then
      done { timestamp = os.time { year = 2026, month = 6, day = 25 } }
    else
      ctx.fallback(ctx, done)
    end
  end

  run("daily", "next", "review")
  wait_for_note "2026-06-25"
  run("daily", "+1")
  wait_for_note(daily.daily({ offset = 1 }).id)
  eq({ "next review", "+1" }, seen)
end

T["daily commands"]["async parsing waits to open, and cancellation leaves the note alone"] = function()
  local finish
  Obsidian.opts.resolvers.date_parse = function(_, done)
    finish = done
  end
  local before = vim.api.nvim_buf_get_name(0)
  run("daily", "some", "day")
  eq(before, vim.api.nvim_buf_get_name(0))
  finish(nil)
  eq(before, vim.api.nvim_buf_get_name(0))

  run("daily", "next", "review")
  finish { timestamp = os.time { year = 2026, month = 6, day = 25 } }
  wait_for_note "2026-06-25"
end

T["daily commands"]["parser errors and malformed results never create a note"] = function()
  local before = vim.api.nvim_buf_get_name(0)
  run("daily", "not-a-date")
  eq(before, vim.api.nvim_buf_get_name(0))

  Obsidian.opts.resolvers.date_parse = function(_, done)
    done(nil, "could not parse")
  end
  run("daily", "missing")
  eq(before, vim.api.nvim_buf_get_name(0))

  Obsidian.opts.resolvers.date_parse = function(_, done)
    done { timestamp = "bad" }
  end
  run("daily", "bad")
  eq(before, vim.api.nvim_buf_get_name(0))
end

T["daily commands"]["dailies accepts only offsets and spans a single offset to today"] = function()
  local original = daily.pick
  local ranges = {}
  daily.pick = function(start_offset, end_offset)
    ranges[#ranges + 1] = { start_offset, end_offset }
  end
  local ok, err = pcall(function()
    run "dailies"
    run("dailies", "-2")
    run("dailies", "2")
    run("dailies", "1", "-2")
  end)
  daily.pick = original
  if not ok then
    error(err)
  end
  eq({ { -5, 0 }, { -2, 0 }, { 0, 2 }, { -2, 1 } }, ranges)

  local ok_invalid = pcall(function()
    run("dailies", "tomorrow")
  end)
  eq(false, ok_invalid)
end

T["daily commands"]["legacy subcommands are hidden but explicitly invokable"] = function()
  local choices = commands.get_completions("", "Obsidian ", #"Obsidian ")
  eq(true, vim.tbl_contains(choices, "daily"))
  eq(true, vim.tbl_contains(choices, "dailies"))
  for _, alias in ipairs { "today", "tomorrow", "yesterday" } do
    eq(false, vim.tbl_contains(choices, alias))
  end

  local picker = require "obsidian.picker"
  local select = picker.select
  local menu
  picker.select = function(items)
    menu = items
  end
  local ok, err = pcall(commands.show_menu, { range = 0 })
  picker.select = select
  if not ok then
    error(err)
  end
  eq(true, vim.tbl_contains(menu, "daily"))
  eq(false, vim.tbl_contains(menu, "today"))

  run("today", "-1")
  wait_for_note(daily.daily({ offset = -1 }).id)
end

T["daily commands"]["legacy commands share the migration message"] = function()
  local log = require "obsidian.log"
  log.set_level(vim.log.levels.INFO)
  local original = vim.notify_once
  local messages = {}
  local seen = {}
  vim.notify_once = function(msg, level)
    if not seen[msg] then
      messages[#messages + 1] = { msg, level }
      seen[msg] = true
    end
  end
  local ok, err = pcall(function()
    run "today"
    wait_for_note(daily.today().id)
    run "tomorrow"
    wait_for_note(daily.tomorrow().id)
    require("obsidian.commands.init-legacy").ObsidianYesterday()
    wait_for_note(daily.yesterday().id)
  end)
  vim.notify_once = original
  if not ok then
    error(err)
  end
  local migration = vim.tbl_filter(function(entry)
    return entry[1]:find(":Obsidian help Breaking-Changes", 1, true) ~= nil
  end, messages)
  eq(1, #migration)
  eq(vim.log.levels.INFO, migration[1][2])
end

return T
