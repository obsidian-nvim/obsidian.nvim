local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set {
  hooks = {
    post_case = function()
      pcall(function()
        require("obsidian.cache").shutdown()
      end)
      if Obsidian and Obsidian.dir then
        vim.fn.delete(tostring(Obsidian.dir), "rf")
      end
      Obsidian = nil
      require("obsidian.lsp.watchfiles").reset_handlers()
    end,
  },
}

local picker = require "obsidian.picker"
local api = require "obsidian.api"
local Path = require "obsidian.path"
local helpers = require "tests.helpers"

local function with_picker_stubs(stubs, fn)
  local original_get_plugin_info = api.get_plugin_info
  local original_default = package.loaded["obsidian.picker._default"]
  local original_telescope = package.loaded["obsidian.picker._telescope"]

  package.loaded["obsidian.picker._default"] = stubs.default
  package.loaded["obsidian.picker._telescope"] = stubs.telescope

  local ok, err = pcall(fn)

  api.get_plugin_info = original_get_plugin_info
  package.loaded["obsidian.picker._default"] = original_default
  package.loaded["obsidian.picker._telescope"] = original_telescope
  picker.get(false)

  if not ok then
    error(err, 0)
  end
end

T["get defers configured picker availability check until first picker call"] = function()
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    default = {
      select = function()
        invoked = invoked + 1
        return "default"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      return nil
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    eq("default", picker.pick {})
    eq(1, calls)
    eq(1, invoked)

    eq("default", picker.pick {})
    eq(1, calls)
    eq(2, invoked)
  end)
end

T["get lazy-resolves select when it is the first picker call"] = function()
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    default = {
      select = function()
        invoked = invoked + 1
        return "default"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      return nil
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    eq("default", picker.select {})
    eq(1, calls)
    eq(1, invoked)
  end)
end

T["get uses configured picker if it becomes available before first picker call"] = function()
  local available = false
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    telescope = {
      select = function()
        invoked = invoked + 1
        return "telescope"
      end,
    },
  }, function()
    api.get_plugin_info = function(name)
      calls = calls + 1
      eq("telescope.nvim", name)
      if available then
        return { path = "/tmp/telescope.nvim" }
      end
    end

    picker.get "telescope.nvim"
    eq(0, calls)

    available = true
    eq("telescope", picker.pick {})
    eq(1, calls)
    eq(1, invoked)

    available = false
    eq("telescope", picker.pick {})
    eq(1, calls)
    eq(2, invoked)
  end)
end

T["find_files_from_cache applies initial query case-insensitively"] = function()
  local dir = Path.temp { suffix = "-obsidian-picker" }
  dir:mkdir { parents = true }
  helpers.write("# Agenda", dir / "Agenda.md")
  helpers.write("# Other", dir / "Other.md")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local picked_values
  local picked_opts
  local original_pick = picker.pick
  picker.pick = function(values, opts)
    picked_values = values
    picked_opts = opts
  end

  eq(true, picker.find_files_from_cache { use_cache = true, query = "agenda" })

  picker.pick = original_pick

  eq(1, #picked_values)
  eq("Agenda.md", picked_values[1].text)
  eq(nil, picked_opts.query)
end

return T
