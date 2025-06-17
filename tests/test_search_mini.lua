local M = require "obsidian.search"

local RefTypes, SearchOpts = M.RefTypes, M.SearchOpts

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["SearchOpts"] = new_set()

T["SearchOpts"]["should initialize from a raw table and resolve to ripgrep options"] = function()
  local opts = {
    sort_by = "modified",
    fixed_strings = true,
    ignore_case = true,
    exclude = { "templates" },
    max_count_per_file = 1,
  }
  eq(
    SearchOpts.to_ripgrep_opts(opts),
    { "--sortr=modified", "--fixed-strings", "--ignore-case", "-g!templates", "-m=1" }
  )
end

T["SearchOpts"]["should not include any options with defaults"] = function()
  eq(SearchOpts.to_ripgrep_opts {}, {})
end

T["SearchOpts"]["should merge with another SearchOpts instance"] = function()
  local opts1 = { fixed_strings = true, max_count_per_file = 1 }
  local opts2 = { fixed_strings = false, ignore_case = true }
  local opt = SearchOpts.merge(opts1, opts2)
  eq(SearchOpts.to_ripgrep_opts(opt), { "--ignore-case", "-m=1" })
end

T["find_matches"] = function()
  local matches = M.find_matches(
    [[
- <https://youtube.com@Fireship>
- [Fireship](https://youtube.com@Fireship)
  ]],
    { RefTypes.NakedUrl }
  )
  eq(2, #matches)
end

return T
