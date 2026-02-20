local Path = require "obsidian.path"
local settings = require "obsidian.settings"
local helpers = dofile "tests/helpers.lua"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["get_vault_config"] = new_set()

T["get_vault_config"]["returns empty config when no .obsidian folder"] = function()
  local tmpdir = Path.temp { suffix = "-obsidian-test" }
  tmpdir:mkdir { parents = true }
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()

  local config = settings.get_vault_config(tmpdir)

  eq(nil, config.daily_notes)
  eq(nil, config.templates)

  vim.fn.delete(tostring(tmpdir), "rf")
end

T["get_vault_config"]["returns daily notes config when daily-notes.json exists"] = function()
  local tmpdir = Path.temp { suffix = "-obsidian-test" }
  tmpdir:mkdir { parents = true }
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()

  helpers.mock_vault_contents(tmpdir, {
    [".obsidian/daily-notes.json"] = [[
{
  "folder": "daily",
  "template": "daily_template.md",
  "format": "yyyy-mm-dd"
}
]],
  })

  local config = settings.get_vault_config(tmpdir)

  eq(nil, config.templates)
  assert(config.daily_notes, "daily_notes should not be nil")
  eq("daily", config.daily_notes.folder)
  eq("daily_template.md", config.daily_notes.template)
  eq("yyyy-mm-dd", config.daily_notes.date_format)

  vim.fn.delete(tostring(tmpdir), "rf")
end

T["get_vault_config"]["returns templates config when templates.json exists"] = function()
  local tmpdir = Path.temp { suffix = "-obsidian-test" }
  tmpdir:mkdir { parents = true }
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()

  helpers.mock_vault_contents(tmpdir, {
    [".obsidian/templates.json"] = [[
{
  "folder": "templates",
  "dateFormat": "yyyy-mm-dd",
  "timeFormat": "HH:mm"
}
]],
  })

  local config = settings.get_vault_config(tmpdir)

  eq(nil, config.daily_notes)
  assert(config.templates, "templates should not be nil")
  eq("templates", config.templates.folder)
  eq("yyyy-mm-dd", config.templates.date_format)
  eq("HH:mm", config.templates.time_format)

  vim.fn.delete(tostring(tmpdir), "rf")
end

T["get_vault_config"]["returns both configs when both files exist"] = function()
  local tmpdir = Path.temp { suffix = "-obsidian-test" }
  tmpdir:mkdir { parents = true }
  local obsidian_dir = tmpdir / ".obsidian"
  obsidian_dir:mkdir()

  helpers.mock_vault_contents(tmpdir, {
    [".obsidian/daily-notes.json"] = [[
{
  "folder": "daily",
  "template": "daily_template.md",
  "format": "yyyy-mm-dd"
}
]],
    [".obsidian/templates.json"] = [[
{
  "folder": "templates",
  "dateFormat": "yyyy-mm-dd",
  "timeFormat": "HH:mm"
}
]],
  })

  local config = settings.get_vault_config(tmpdir)

  assert(config.daily_notes, "daily_notes should not be nil")
  eq("daily", config.daily_notes.folder)
  eq("daily_template.md", config.daily_notes.template)
  eq("yyyy-mm-dd", config.daily_notes.date_format)

  assert(config.templates, "templates should not be nil")
  eq("templates", config.templates.folder)
  eq("yyyy-mm-dd", config.templates.date_format)
  eq("HH:mm", config.templates.time_format)

  vim.fn.delete(tostring(tmpdir), "rf")
end

return T
