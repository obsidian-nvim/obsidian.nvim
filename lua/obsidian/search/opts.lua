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

local search_defaults = {
  sort = false,
  include_templates = false,
  ignore_case = false,
}

---@param opts obsidian.SearchOpts
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

return M
