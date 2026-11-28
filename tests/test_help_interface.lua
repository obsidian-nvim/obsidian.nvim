local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local Path = require "obsidian.path"
local help = require "obsidian.interfaces.help"
local runtime = require "obsidian.runtime"
local picker = require "obsidian.picker"

local T = new_set()

T["help uses the plugin docs directory for pick and grep"] = function()
  local root = Path.new(vim.fn.tempname())
  local docs = root / "docs"
  docs:mkdir { parents = true }
  vim.fn.writefile({ "# Intro" }, tostring(docs / "Intro.md"))

  local original_info = runtime.get_plugin_info
  local original_find = picker.find_notes
  local original_grep = picker.grep_notes
  local original_cmd = vim.cmd
  local found, grepped, edited
  local ok, err = pcall(function()
    runtime.get_plugin_info = function(name)
      eq("obsidian.nvim", name)
      return { path = tostring(root) }
    end
    picker.find_notes = function(opts)
      found = opts
    end
    picker.grep_notes = function(opts)
      grepped = opts
    end
    vim.cmd = function(command)
      edited = command
    end

    eq(docs, help.get_dir())
    help.pick "Intro"
    eq("edit " .. tostring(docs / "Intro.md"), edited)
    eq(nil, found)

    help.pick "missing"
    eq(docs, found.dir)
    eq("missing", found.query)
    eq("Obsidian Help", found.prompt_title)

    help.grep "keyword"
    eq(docs, grepped.dir)
    eq("keyword", grepped.query)
  end)
  runtime.get_plugin_info = original_info
  picker.find_notes = original_find
  picker.grep_notes = original_grep
  vim.cmd = original_cmd
  vim.fn.delete(tostring(root), "rf")
  assert(ok, err)
end

return T
