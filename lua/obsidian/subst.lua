local Path = require "obsidian.path"
local log = require "obsidian.log"
local util = require "obsidian.util"

--- Metadata surrounding a request to substitute template variables.
---
---@class obsidian.SubstitutionContext
---@field action obsidian.SubstitutionContext.Action
---@field client obsidian.Client
---@field template_path obsidian.Path|string|?
---@field target_location [number, number, number, number]|?
---@field target_note obsidian.Note|?
---
---@alias obsidian.SubstitutionContext.Action "clone_template" | "insert_template"

--- Provides a value for the corresponding placeholder variable.
---
--- @alias obsidian.SubstitutionFunction fun(ctx: obsidian.SubstitutionContext): string|?

local M = {}

--- Resolve a template name to a path.
---
---@param template_path string|obsidian.Path
---@param client obsidian.Client
---
---@return obsidian.Path
local resolve_template_path = function(template_path, client)
  local templates_dir = client:templates_dir()
  if templates_dir == nil then
    error "Templates folder is not defined or does not exist"
  end

  ---@type obsidian.Path|?
  local resolved_path
  local paths_to_check = { templates_dir / tostring(template_path), Path:new(template_path) }
  for _, path in ipairs(paths_to_check) do
    if path:is_file() then
      resolved_path = path
      break
    elseif not vim.endswith(tostring(path), ".md") then
      local path_with_suffix = Path:new(tostring(path) .. ".md")
      if path_with_suffix:is_file() then
        resolved_path = path_with_suffix
        break
      end
    end
  end

  if resolved_path == nil then
    error(string.format("Template '%s' not found", template_path))
  end

  return resolved_path
end

--- Returns a validated context, otherwise returns nil and an error message.
---
---@param expected_action obsidian.SubstitutionContext.Action
---@param ctx obsidian.SubstitutionContext
---@return obsidian.SubstitutionContext
M.assert_valid_context = function(ctx, expected_action)
  assert(ctx.action == expected_action, string.format("unexpected substitution action: %s", ctx.action))
  assert(ctx.client, "obsidian.nvim client is required")
  assert(ctx.template_path, "template name is required")
  local template_path = assert(
    resolve_template_path(ctx.template_path, ctx.client),
    string.format("template does not exist: %s", ctx.template_path)
  )

  if ctx.action == "clone_template" then
    assert(ctx.target_note and ctx.target_note.path:parent(), "target note is required to clone templates")
  elseif ctx.action == "insert_template" then
    assert(ctx.target_location, "cursor location is required to insert templates")
  else
    error(string.format("unrecognized substitution action: %s", ctx.action))
  end

  ---@type obsidian.SubstitutionContext
  return {
    action = ctx.action,
    client = ctx.client,
    template_path = template_path,
    target_note = ctx.target_note,
    target_location = ctx.target_location,
  }
end

---@param var_name string
---@param subst obsidian.SubstitutionFunction|string
---@param ctx obsidian.SubstitutionContext
---@return string|?
local function substitute_variable_safely(var_name, subst, ctx)
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
    methods["title"] = ctx.target_note.title or ctx.target_note:display_name()
  end

  if not methods["id"] then
    methods["id"] = tostring(ctx.target_note.id)
  end

  if not methods["path"] and ctx.target_note.path then
    methods["path"] = tostring(ctx.target_note.path)
  end

  -- Replace known variables.
  for key, subst in pairs(methods) do
    for m_start, m_end in util.gfind(text, "{{" .. key .. "}}", nil, true) do
      local value = substitute_variable_safely(key, subst, ctx)
      if value then
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
