local Path = require "obsidian.path"
local compat = require "obsidian.compat"

--- TODO: a bit weird to have these two...

---@class obsidian.SearchOpts
---
---@field sort boolean|?
---@field include_templates boolean|?
---@field ignore_case boolean|?
---@field default function?

---@class obsidian.search.SearchOpts
---
---@field sort_by obsidian.config.SortBy|?
---@field sort_reversed boolean|?
---@field fixed_strings boolean|?
---@field ignore_case boolean|?
---@field smart_case boolean|?
---@field exclude string[]|? paths to exclude
---@field max_count_per_file integer|?
---@field escape_path boolean|?
---@field include_non_markdown boolean|?

local M = {}

M._BASE_CMD = { "rg", "--no-config", "--type=md" }
M._SEARCH_CMD = compat.flatten { M._BASE_CMD, "--json" }
M._FIND_CMD = compat.flatten { M._BASE_CMD, "--files" }

local as_tbl = function(self)
  local fields = {}
  for k, v in pairs(self) do
    if not vim.startswith(k, "__") then
      fields[k] = v
    end
  end
  return fields
end

---@param one obsidian.search.SearchOpts|table
---@param other obsidian.search.SearchOpts|table
---@return obsidian.search.SearchOpts
local merge = function(one, other)
  return vim.tbl_extend("force", as_tbl(one), as_tbl(other))
end

M._merge = merge

---@param opts obsidian.search.SearchOpts
---@param path string
local add_exclude = function(opts, path)
  if opts.exclude == nil then
    opts.exclude = {}
  end
  opts.exclude[#opts.exclude + 1] = path
end

---@param opts obsidian.search.SearchOpts
---@return string[]
M.to_ripgrep_opts = function(opts)
  -- vim.validate("opts.exclude", opts.exclude, "table", true)

  local ret = {}

  if opts.sort_by ~= nil then
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

local search_defaults = {
  sort = false,
  include_templates = false,
  ignore_case = false,
}

---@param opts obsidian.SearchOpts|boolean|?
---@param additional_opts obsidian.search.SearchOpts|?
---
---@return obsidian.search.SearchOpts
---
M._prepare = function(opts, additional_opts)
  opts = opts or search_defaults

  local search_opts = {}

  if opts.sort then
    search_opts.sort_by = Obsidian.opts.search.sort_by
    search_opts.sort_reversed = Obsidian.opts.search.sort_reversed
  end

  if not opts.include_templates and Obsidian.opts.templates ~= nil and Obsidian.opts.templates.folder ~= nil then
    add_exclude(search_opts, tostring(Obsidian.opts.templates.folder))
  end

  if opts.ignore_case then
    search_opts.ignore_case = true
  end

  if additional_opts ~= nil then
    search_opts = merge(search_opts, additional_opts)
  end

  return search_opts
end

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
    path = assert(vim.fn.fnameescape(path))
  end

  return compat.flatten {
    M._SEARCH_CMD,
    M.to_ripgrep_opts(opts),
    search_terms,
    path,
  }
end

--- Build the 'rg' command for finding files.
---
---@param path string|?
---@param term string|?
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_find_cmd = function(path, term, opts)
  opts = opts and opts or {}
  opts = vim.tbl_extend("keep", opts, {
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
    ignore_case = true,
  })

  local additional_opts = {}

  if term ~= nil then
    if opts.include_non_markdown then
      term = "*" .. term .. "*"
    elseif not vim.endswith(term, ".md") then
      term = "*" .. term .. "*.md"
    else
      term = "*" .. term
    end
    additional_opts[#additional_opts + 1] = "-g"
    additional_opts[#additional_opts + 1] = term
  end

  if opts.ignore_case then
    additional_opts[#additional_opts + 1] = "--glob-case-insensitive"
  end

  if path ~= nil and path ~= "." then
    if opts.escape_path then
      path = assert(vim.fn.fnameescape(tostring(path)))
    end
    additional_opts[#additional_opts + 1] = path
  end

  return compat.flatten { M._FIND_CMD, M.to_ripgrep_opts(opts), additional_opts }
end

--- Build the 'rg' grep command for pickers.
---
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_grep_cmd = function(opts)
  opts = opts and opts or {}

  opts = vim.tbl_extend("keep", opts, {
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
    smart_case = true,
    fixed_strings = true,
  })

  return compat.flatten {
    M._BASE_CMD,
    M.to_ripgrep_opts(opts),
    "--column",
    "--line-number",
    "--no-heading",
    "--with-filename",
    "--color=never",
  }
end

return M
