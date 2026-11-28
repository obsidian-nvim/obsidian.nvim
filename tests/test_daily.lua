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

T["daily_note_path"]["should support Sunday as the start of the week"] = function()
  Obsidian.opts.daily_notes.date_format = "GGGG-[W]WW/YYYY-MM-DD"
  Obsidian.opts.daily_notes.start_of_week = 0

  local sunday = os.time { year = 2026, month = 1, day = 4, hour = 12 }
  local path, id = M.daily_note_path(sunday)
  assert(vim.endswith(tostring(path), "2026-W02/2026-01-04.md"))
  eq("2026-01-04", id)
end

T["daily_note_path"]["should resolve from an explicit vault directory"] = function()
  local dir = Obsidian.dir / "nested-vault"
  dir:mkdir()

  local note = M.daily { date = os.time(), dir = dir }
  eq(true, dir:is_parent_of(note.path))
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

local workspace_tests, child = h.child_vault {
  post_case = [[
    for _, root in ipairs(vim.g.daily_test_roots or {}) do
      vim.fn.delete(root, 'rf')
    end
  ]],
}
T["workspace"] = workspace_tests

workspace_tests["commands and the picker use the explicitly selected workspace"] = function()
  local result = child.lua [[
    local a = tostring(Obsidian.dir)
    local b = a .. "-other"
    vim.g.daily_test_roots = { a, b }
    vim.fn.mkdir(b .. "/templates", "p")
    vim.fn.writefile({ "# Note A" }, a .. "/note.md")
    vim.fn.writefile({ "# Template A" }, a .. "/templates/daily.md")
    vim.fn.writefile({ "# Template B" }, b .. "/templates/daily.md")
    require("obsidian").setup {
      legacy_commands = false,
      ui = { enable = false },
      templates = { folder = "templates" },
      daily_notes = { folder = "daily", template = "daily.md" },
      workspaces = {
        { name = "a", path = a },
        { name = "b", path = b, overrides = {
          daily_notes = { folder = "journal", date_format = "YYYY/[day-]MM-DD" },
          frontmatter = { enabled = false },
        } },
      },
    }
    vim.cmd("edit " .. vim.fn.fnameescape(a .. "/note.md"))
    -- Model an already-attached note, independently of filetype autocmds.
    vim.b.obsidian_buffer = true
    assert(require("obsidian.api").find_workspace(vim.api.nvim_buf_get_name(0)).name == "a")
    vim.cmd("Obsidian workspace b")
    assert(Obsidian.workspace.name == "b")

    local expected = b .. "/journal/2026/day-06-25.md"
    local daily = require "obsidian.daily"
    local date = os.time { year = 2026, month = 6, day = 25, hour = 12 }
    local actual = tostring(daily.daily_note_path(date))
    local picker = require "obsidian.picker"
    local picker_path
    picker.select = function(entries)
      picker_path = entries[1].filename
    end
    require("obsidian.resolvers").builtin.date({ offset_start = 0, offset_end = 0 }, function() end)
    local expected_preview = b .. "/journal/" .. os.date "%Y/day-%m-%d.md"
    vim.cmd("Obsidian today 2026-06-25")
    return {
      path_matches = actual == expected,
      preview_matches = picker_path == expected_preview,
      wrong_vault = vim.fn.filereadable(a .. "/journal/2026/day-06-25.md") == 1,
      contents = vim.fn.filereadable(expected) == 1 and vim.fn.readfile(expected) or {},
    }
  ]]
  eq({ path_matches = true, preview_matches = true, wrong_vault = false, contents = { "# Template B" } }, result)
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

T["dailies"]["picker previews existing notes and prompts to create missing notes"] = function()
  local today = M.daily_note_path()
  h.write("# Today", today)

  local picker = require "obsidian.picker"
  local original_select = picker.select
  local existing_lines, missing_lines, bufhidden
  picker.select = function(items, opts, on_choice)
    for _, item in ipairs(items) do
      local preview = opts.preview_item(item)
      local lines = vim.api.nvim_buf_get_lines(preview.buf, 0, -1, false)
      if vim.uv.fs_stat(item.filename) then
        existing_lines = lines
      else
        missing_lines = lines
      end
      bufhidden = vim.bo[preview.buf].bufhidden
      vim.api.nvim_buf_delete(preview.buf, { force = true })
    end
    on_choice {}
  end

  local ok, err = pcall(function()
    require("obsidian.resolvers").builtin.date({
      offset_start = 0,
      offset_end = 1,
    }, function() end)
  end)
  picker.select = original_select
  if not ok then
    error(err)
  end

  eq({ "# Today" }, existing_lines)
  eq({ "Select to create this daily note." }, missing_lines)
  eq("wipe", bufhidden)
end

return T
