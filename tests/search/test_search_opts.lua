local M = require "obsidian.search.ripgrep"
local Opts = require "obsidian.search.opts"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

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

T["should disable sort when sort_by is false"] = function()
  local opts = {
    sort_by = false,
  }
  eq(M._generate_args(opts), {})
end

T["should resolve workspace defaults without overriding explicit false"] = function()
  local original_obsidian = Obsidian
  Obsidian = {
    opts = {
      search = { sort_by = "modified", sort_reversed = true },
      templates = {},
      file = { ignore_filters = { "archive" } },
    },
  }

  local resolved = Opts.resolve(".", { sort_by = false, sort_reversed = false })
  Obsidian = original_obsidian

  eq(false, resolved.sort_by)
  eq(false, resolved.sort_reversed)
  eq({ "archive" }, resolved.exclude)
end

T["should derive case sensitivity from ignorecase and smartcase"] = function()
  local original_ignorecase = vim.o.ignorecase
  local original_smartcase = vim.o.smartcase
  local results = {}

  vim.o.ignorecase = false
  vim.o.smartcase = false
  results.ignorecase_off = Opts.should_ignore_case "lower"

  vim.o.ignorecase = true
  results.smartcase_off = Opts.should_ignore_case "UPPER"

  vim.o.smartcase = true
  results.lowercase_query = Opts.should_ignore_case "lower"
  results.uppercase_query = Opts.should_ignore_case "Upper"

  vim.o.ignorecase = original_ignorecase
  vim.o.smartcase = original_smartcase
  eq({
    ignorecase_off = false,
    smartcase_off = true,
    lowercase_query = true,
    uppercase_query = false,
  }, results)
end

return T
