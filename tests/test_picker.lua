local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local picker = require "obsidian.picker"
local api = require "obsidian.api"

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
      pick = function()
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

T["get uses configured picker if it becomes available before first picker call"] = function()
  local available = false
  local calls = 0
  local invoked = 0

  with_picker_stubs({
    telescope = {
      pick = function()
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

return T
