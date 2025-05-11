local Path = require "obsidian.path"
local log = require "obsidian.log"
local util = require "obsidian.util"

--- Metadata surrounding a request to substitute template variables.
---
---@class obsidian.SubstitutionContext
---@field action obsidian.SubstitutionContext.Action
---@field client obsidian.Client
---@field template string|obsidian.Path|?
---@field target_location [number, number, number, number]|?
---@field target_note obsidian.Note|?
---
---@alias obsidian.SubstitutionContext.Action "clone_template" | "insert_template"

--- Provides a value for the corresponding placeholder variable.
---
--- @alias obsidian.SubstitutionFunction fun(ctx: obsidian.SubstitutionContext): string|?

--- Resolve the template path and returns it. Otherwise, if invalid, then returns nil and an error message.
---
--- @overload fun(client: obsidian.Client, template: string|obsidian.Path|?): obsidian.Path, nil
--- @overload fun(client: obsidian.Client, template: string|obsidian.Path|?): nil, string
local resolve_template_path = function(client, template)
  if template == nil then
    return nil, "Template is not defined"
  end

  local templates_dir = client:templates_dir()
  if templates_dir == nil then
    return nil, "Templates folder is not defined or does not exist"
  end

  ---@type obsidian.Path|?
  local resolved_path
  local paths_to_check = { templates_dir / tostring(template), Path:new(template) }
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
    return nil, string.format("Template '%s' not found", template)
  end

  return resolved_path, nil
end

local M = {}

--- Validates and resolves context values.
---
---@param expected_action obsidian.SubstitutionContext.Action
---@param ctx obsidian.SubstitutionContext
---@return obsidian.SubstitutionContext
M.assert_valid_context = function(ctx, expected_action)
  if ctx.action == "clone_template" then
    assert(ctx.action == expected_action, string.format("unexpected action: %s", ctx.action))
    assert(ctx.target_note, "target note must be defined")
    assert(ctx.target_note.path:parent(), "target note must include a parent folder in its path")
  elseif ctx.action == "insert_template" then
    assert(ctx.action == expected_action, string.format("unexpected action: %s", ctx.action))
    assert(ctx.target_location, "cursor location must be defined")
  else
    error(string.format("unknown action: %s", ctx.action))
  end

  local valid_client = assert(ctx.client, "obsidian.nvim client is required")
  local valid_template = assert(resolve_template_path(valid_client, ctx.template))

  ---@type obsidian.SubstitutionContext
  return {
    action = ctx.action,
    client = valid_client,
    template = valid_template,
    target_note = ctx.target_note,
    target_location = ctx.target_location,
  }
end

---@param var_name string
---@param subst obsidian.SubstitutionFunction|string
---@param ctx obsidian.SubstitutionContext
---@return string|?
local function get_subst_value_safely(var_name, subst, ctx)
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
  local substitutions = vim.deepcopy(ctx.client.opts.templates.substitutions or {})

  if not substitutions["date"] then
    substitutions["date"] = tostring(os.date(ctx.client.opts.templates.date_format or "%Y-%m-%d"))
  end

  if not substitutions["time"] then
    substitutions["time"] = tostring(os.date(ctx.client.opts.templates.time_format or "%H:%M"))
  end

  if not substitutions["title"] and ctx.target_note then
    substitutions["title"] = ctx.target_note.title or ctx.target_note:display_name()
  end

  if not substitutions["id"] and ctx.target_note then
    substitutions["id"] = tostring(ctx.target_note.id)
  end

  if not substitutions["path"] and ctx.target_note then
    substitutions["path"] = tostring(ctx.target_note.path)
  end

  -- Replace known variables.
  for key, subst in pairs(substitutions) do
    for m_start, m_end in util.gfind(text, "{{" .. key .. "}}", nil, true) do
      local value = get_subst_value_safely(key, subst, ctx)
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
