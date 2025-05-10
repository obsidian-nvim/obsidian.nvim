local util = require "obsidian.util"

--- Provides context about the request to substitute a template variable.
---
---@class obsidian.SubstitutionContext
---@field client obsidian.Client
---@field cursor_location [number, number, number, number]|?
---@field template_name string|?
---@field note_override obsidian.Note|?
---@field path_override obsidian.Path|?

local M = {}

--- Substitute variables inside the given text.
---
---@param text string
---@param ctx obsidian.SubstitutionContext
---
---@return string
M.substitute_template_variables = function(text, ctx)
  local methods = vim.deepcopy(ctx.client.opts.templates.substitutions or {})

  if not methods["date"] then
    methods["date"] = function()
      local date_format = ctx.client.opts.templates.date_format or "%Y-%m-%d"
      return tostring(os.date(date_format))
    end
  end

  if not methods["time"] then
    methods["time"] = function()
      local time_format = ctx.client.opts.templates.time_format or "%H:%M"
      return tostring(os.date(time_format))
    end
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
      ---@type string
      local value
      if type(subst) == "string" then
        value = subst
      else
        value = subst()
        -- cache the result
        methods[key] = value
      end
      text = string.sub(text, 1, m_start - 1) .. value .. string.sub(text, m_end + 1)
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
