local util = require "obsidian.util"

--- Provides context about the request to substitute a template variable.
---
---@class obsidian.SubstitutionContext
---@field client obsidian.Client
---@field cursor_location [number, number, number, number]|?
---@field template_name string|?
---@field note_override obsidian.Note|?
---@field path_override obsidian.Path|?

--- Provides a variable's value within the provided substitution context.
--- NOTE: Non-nil return values are coerced into strings with neovim's tostring() function.
---
--- @alias obsidian.SubstitutionFunction fun(ctx: obsidian.SubstitutionContext): any|?

local M = {}

---@param subst obsidian.SubstitutionFunction|string
---@param ctx obsidian.SubstitutionContext
---@return any|nil
local function get_subst_value(subst, ctx)
  if type(subst) == "string" then
    return subst
  else
    local ok, value = pcall(subst, ctx)
    return ok and value and tostring(value) or nil
  end
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

  -- Replace known variables.
  for key, subst in pairs(methods) do
    for m_start, m_end in util.gfind(text, "{{" .. key .. "}}", nil, true) do
      local value = get_subst_value(subst, ctx)
      if value and string.len(value) > 0 then
        text = string.sub(text, 1, m_start - 1) .. value .. string.sub(text, m_end + 1)
      end
    end
  end

  -- Find unknown variables and prompt for them.
  for m_start, m_end in util.gfind(text, "{{[^}]+}}") do
    local key = util.strip_whitespace(string.sub(text, m_start + 2, m_end - 2))
    local value = util.input(string.format("Enter value for '%s' (<cr> to skip): ", key))
    if value and string.len(value) > 0 then
      text = string.sub(text, 1, m_start - 1) .. value .. string.sub(text, m_end + 1)
    end
  end

  return text
end

return M
