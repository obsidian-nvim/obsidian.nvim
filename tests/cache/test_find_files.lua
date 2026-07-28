local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local Path = require "obsidian.path"
local picker = require "obsidian.picker"

local T = new_set {}

T["find_files_from_cache applies initial query case-insensitively"] = function()
  local dir = Path.temp { suffix = "-obsidian-picker" }
  dir:mkdir { parents = true }
  h.write("# Agenda", dir / "Agenda.md")
  h.write("# Other", dir / "Other.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local picked_values
  local picked_opts
  local original_select = picker.select
  picker.select = function(values, opts)
    picked_values = values
    picked_opts = opts
  end

  eq(true, cache.find_files { use_cache = true, query = "agenda" })

  picker.select = original_select

  eq(1, #picked_values)
  eq("Agenda", picked_values[1].text)
  eq(true, picked_opts.allow_multiple)
  eq(nil, picked_opts.query)
end

return T
