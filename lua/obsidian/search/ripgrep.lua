local Path = require "obsidian.path"
local util = require "obsidian.util"

local M = {}

local BASE_CMD = {
  "rg",
  "--no-config",
  "--type-add",
  "md:*.qmd",
  "--type-add",
  "md:*.base",
}

-- `--crlf` makes ripgrep treat `\r\n` as a line terminator so that `$`
-- anchors in search patterns (e.g. frontmatter tag lists) also match files
-- with DOS line endings. See https://github.com/obsidian-nvim/obsidian.nvim/issues/903.
local SEARCH_CMD = util.flatten { BASE_CMD, "--type=md", "--json", "--crlf" }
local FIND_CMD = util.flatten { BASE_CMD, "--files" }

---@param opts obsidian.search.SearchOpts
---@return string[]
local generate_args = function(opts)
  -- vim.validate("opts.exclude", opts.exclude, "table", true)

  local ret = {}

  if opts.sort_by then
    local sort = "sortr" -- default sort is reverse
    if opts.sort_reversed == false then
      sort = "sort"
    end
    ret[#ret + 1] = "--" .. sort .. "=" .. opts.sort_by
  end

  if opts.fixed_strings then
    ret[#ret + 1] = "--fixed-strings"
  end

  if opts.ignore_case then
    ret[#ret + 1] = "--ignore-case"
  end

  if opts.smart_case then
    ret[#ret + 1] = "--smart-case"
  end

  if opts.exclude ~= nil then
    for _, path in ipairs(opts.exclude) do
      ret[#ret + 1] = "-g!" .. path
    end
  end

  if opts.max_count_per_file ~= nil then
    ret[#ret + 1] = "-m=" .. opts.max_count_per_file
  end

  return ret
end

M._generate_args = generate_args

---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_search_cmd = function(dir, term, opts)
  opts = opts and opts or {}

  local search_terms
  if type(term) == "string" then
    search_terms = { "-e", term }
  else
    search_terms = {}
    for _, t in ipairs(term) do
      search_terms[#search_terms + 1] = "-e"
      search_terms[#search_terms + 1] = t
    end
  end

  local path = tostring(Path.new(dir):resolve { strict = true })
  if opts.escape_path then
    path = vim.fn.fnameescape(path)
  end

  return util.flatten {
    SEARCH_CMD,
    generate_args(opts),
    search_terms,
    path,
  }
end

---@param path string?
---@param opts obsidian.search.SearchOpts?
---@return string[]
M.build_find_cmd = function(path, opts)
  opts = opts or {}
  local search_opts = Obsidian and Obsidian.opts and Obsidian.opts.search or {}
  opts = vim.tbl_extend("keep", opts, {
    sort_by = search_opts.sort_by,
    sort_reversed = search_opts.sort_reversed,
    ignore_case = true,
  })

  local additional_opts = {}
  if not opts.include_non_markdown then
    additional_opts[#additional_opts + 1] = "--type=md"
  end

  if path ~= nil and path ~= "." then
    additional_opts[#additional_opts + 1] = path
  end

  return util.flatten {
    FIND_CMD,
    generate_args(opts),
    additional_opts,
  }
end

--- Build the 'rg' grep command for pickers.
---
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_grep_cmd = function(opts)
  opts = opts and opts or {}
  local search_opts = Obsidian and Obsidian.opts and Obsidian.opts.search or {}

  opts = vim.tbl_extend("keep", opts, {
    sort_by = search_opts.sort_by,
    sort_reversed = search_opts.sort_reversed,
    smart_case = true,
    fixed_strings = true,
  })

  return util.flatten {
    BASE_CMD,
    "--type=md",
    generate_args(opts),
    "--column",
    "--line-number",
    "--no-heading",
    "--with-filename",
    "--color=never",
  }
end

return M
