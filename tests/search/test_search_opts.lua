local M = require "obsidian.search.ripgrep"
local Opts = require "obsidian.search.opts"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T = new_set()

T["should initialize from a raw table and resolve to ripgrep options"] = function()
  local opts = {
    sort_by = "modified",
    fixed_strings = true,
    ignore_case = true,
    exclude = { "templates" },
    max_count_per_file = 1,
  }
  eq(M._generate_args(opts), { "--sortr=modified", "--fixed-strings", "--ignore-case", "-g!templates", "-m=1" })
end

T["should not include any options with defaults"] = function()
  eq(M._generate_args {}, {})
end

T["should merge with another SearchOpts instance"] = function()
  local opts1 = { fixed_strings = true, max_count_per_file = 1 }
  local opts2 = { fixed_strings = false, ignore_case = true }
  local opt = Opts._merge(opts1, opts2)
  eq(M._generate_args(opt), { "--ignore-case", "-m=1" })
end

return T
