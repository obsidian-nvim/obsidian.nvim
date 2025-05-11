local log = require "obsidian.log"
local util = require "obsidian.util"

--- Metadata surrounding a request to substitute template variables.
---
---@class obsidian.SubstitutionContext
---@field client obsidian.Client
---@field cursor_location [number, number, number, number]|?
---@field template_name string|?
---@field note_override obsidian.Note|?
---@field path_override obsidian.Path|?

--- Provides a value for the corresponding variable placeholder.
---
--- NOTE: Non-nil return values are coerced into strings with neovim's tostring() function.
---
--- @alias obsidian.SubstitutionFunction fun(ctx: obsidian.SubstitutionContext): any|?

local M = {}

---@param var_name string
---@param subst obsidian.SubstitutionFunction|string
---@param ctx obsidian.SubstitutionContext
---@return string|?
local function get_subst_value(var_name, subst, ctx)
  if type(subst) == "string" then
    return subst
  elseif vim.is_callable(subst) then
    local ok, value = pcall(subst, ctx)
    if not ok then
      log.error('"%s" substitution error: %s', var_name, tostring(value))
      log.debug('"%s" substitution context: %s', var_name, tostring(ctx))
    elseif type(value) ~= "string" then
      log.error('"%s" substitution error: ignoring value=%s (not a string)', var_name, tostring(value))
      log.debug('"%s" substitution context: %s', var_name, tostring(ctx))
    else
      return value
    end
  elseif subst ~= nil then
    log.error('"%s" substitution error: ignoring value=%s (not a string or callable)', var_name, tostring(subst))
    log.debug('"%s" substitution context: %s', var_name, tostring(ctx))
  end
  -- Fallback to user input
  return util.input(string.format("Enter value for '%s' (<cr> to skip): ", var_name))
end

--- Substitute variables inside the given text.
---
---@param text string
---@param ctx obsidian.SubstitutionContext
---
---@return string
M.substitute_template_variables = function(text, ctx)
  local methods = vim.deepcopy(ctx.client.opts.templates.substitutions or {})

  if not methods["date"] then
    local date_format = ctx.client.opts.templates.date_format or "%Y-%m-%d"
    methods["date"] = tostring(os.date(date_format))
  end

  if not methods["time"] then
    local time_format = ctx.client.opts.templates.time_format or "%H:%M"
    methods["time"] = tostring(os.date(time_format))
  end

  if not methods["title"] then
    methods["title"] = ctx.note_override.title or ctx.note_override:display_name()
  end

  if not methods["id"] then
    methods["id"] = tostring(ctx.note_override.id)
  end

  if not methods["path"] and ctx.note_override.path then
    methods["path"] = tostring(ctx.note_override.path)
  end

  for m_start, m_end in util.gfind(text, "{{[^}]+}}") do
    local key = util.strip_whitespace(string.sub(text, m_start + 2, m_end - 2))
    local value = get_subst_value(key, methods[key], ctx)
    if value and string.len(value) > 0 then
      text = string.sub(text, 1, m_start - 1) .. value .. string.sub(text, m_end + 1)
    end
  end

  return text
end

return M
