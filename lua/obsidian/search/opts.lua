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

M.as_tbl = function(self)
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
M.merge = function(one, other)
  return vim.tbl_extend("force", M.as_tbl(one), M.as_tbl(other))
end

---@param opts obsidian.search.SearchOpts
---@param path string
M.add_exclude = function(opts, path)
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
    M.SearchOpts.add_exclude(search_opts, tostring(Obsidian.opts.templates.folder))
  end

  if opts.ignore_case then
    search_opts.ignore_case = true
  end

  if additional_opts ~= nil then
    search_opts = M.SearchOpts.merge(search_opts, additional_opts)
  end

  return search_opts
end

return M
