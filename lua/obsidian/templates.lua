local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"
local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}

--- Resolve a template name to a path.
---
---@param template_name string|obsidian.Path
---@param templates_dir obsidian.Path|?
---
---@return obsidian.Path
M.resolve_template = function(template_name, templates_dir)
  ---@type obsidian.Path|?
  local template_path
  local paths_to_check = { Path.new(template_name) }

  if templates_dir then
    table.insert(paths_to_check, templates_dir and templates_dir / tostring(template_name))
  end

  for _, path in ipairs(paths_to_check) do
    if path:is_file() then
      template_path = path
      break
    elseif not vim.endswith(tostring(path), ".md") then
      local path_with_suffix = Path.new(tostring(path) .. ".md")
      if path_with_suffix:is_file() then
        template_path = path_with_suffix
        break
      end
    end
  end

  if template_path == nil then
    error(string.format("Template '%s' not found", template_name))
  end

  return template_path
end

--- Substitute variables inside the given text.
---
---@param text string
---@param ctx obsidian.TemplateContext
---
---@return string
M.substitute_template_variables = function(text, ctx)
  local methods = vim.deepcopy(Obsidian.opts.templates.substitutions or {})

  -- Replace known variables.
  for key, subst in pairs(methods) do
    local key_pattern = vim.pesc(key)
    if type(subst) == "string" then
      text = string.gsub(text, "{{" .. key_pattern .. "}}", subst)
    else
      text = string.gsub(text, "{{" .. key_pattern .. ":([^}]*)}}", function(suffix)
        return subst(ctx, vim.trim(suffix))
      end)
      text = string.gsub(text, "{{" .. key_pattern .. "}}", function()
        return subst(ctx)
      end)
    end
  end

  -- Find unknown variables and prompt for them.
  for m_start, m_end in util.gfind(text, "{{[^}]+}}") do
    local key = vim.trim(string.sub(text, m_start + 2, m_end - 2))
    local value = api.input(string.format("Enter value for '%s' (<cr> to skip): ", key))
    if value and string.len(value) > 0 then
      text = string.sub(text, 1, m_start - 1) .. value .. string.sub(text, m_end + 1)
    end
  end

  return text
end

--- Clone template to a new note.
---
---@param ctx obsidian.CloneTemplateContext
---
---@return obsidian.Note
M.clone_template = function(ctx)
  local note_path = Path.new(ctx.destination_path)
  assert(note_path:parent()):mkdir { parents = true, exist_ok = true }

  local template_path = M.resolve_template(ctx.template_name, ctx.templates_dir)

  -- Check if the template uses templater syntax and should be executed via templater.
  local use_templater = Obsidian.opts.templater
    and Obsidian.opts.templater.enabled
    and M.is_templater_template(ctx.template_name, ctx.templates_dir)

  if use_templater then
    local lines, used_templater = M.substitute_with_templater(template_path, ctx)
    if used_templater then
      local note_file, write_err = io.open(tostring(note_path), "w")
      if not note_file then
        error(string.format("Unable to write note at '%s': %s", note_path, tostring(write_err)))
      end
      for _, line in ipairs(lines) do
        note_file:write(line .. "\n")
      end
      assert(note_file:close())

      local new_note = Note.from_file(note_path)

      if ctx.partial_note ~= nil then
        new_note.id = ctx.partial_note.id
        new_note.title = ctx.partial_note.title
        for _, alias in ipairs(ctx.partial_note.aliases) do
          new_note:add_alias(alias)
        end
        for _, tag in ipairs(ctx.partial_note.tags) do
          new_note:add_tag(tag)
        end
      end

      return new_note
    end
  end

  -- Standard built-in template substitution.
  local template_file, read_err = io.open(tostring(template_path), "r")
  if not template_file then
    error(string.format("Unable to read template at '%s': %s", template_path, tostring(read_err)))
  end

  local note_file, write_err = io.open(tostring(note_path), "w")
  if not note_file then
    error(string.format("Unable to write note at '%s': %s", note_path, tostring(write_err)))
  end

  for line in template_file:lines "L" do
    line = M.substitute_template_variables(line, ctx)
    note_file:write(line)
  end

  assert(template_file:close())
  assert(note_file:close())

  local new_note = Note.from_file(note_path)

  if ctx.partial_note ~= nil then
    -- Transfer fields from `ctx.partial_note`.
    new_note.id = ctx.partial_note.id
    new_note.title = ctx.partial_note.title
    for _, alias in ipairs(ctx.partial_note.aliases) do
      new_note:add_alias(alias)
    end
    for _, tag in ipairs(ctx.partial_note.tags) do
      new_note:add_tag(tag)
    end
  end

  return new_note
end

---Insert a template at the given location.
---
---@param ctx obsidian.InsertTemplateContext
---
---@return obsidian.Note
M.insert_template = function(ctx)
  local buf, win, row, _ = unpack(ctx.location)
  if ctx.partial_note == nil then
    ctx.partial_note = Note.from_buffer(buf)
  end

  local template_path = M.resolve_template(ctx.template_name, ctx.templates_dir)

  -- Check if the template uses templater syntax and should be executed via templater.
  local use_templater = Obsidian.opts.templater
    and Obsidian.opts.templater.enabled
    and M.is_templater_template(ctx.template_name, ctx.templates_dir)

  ---@type string[]
  local template_lines

  if use_templater then
    local lines, used_templater = M.substitute_with_templater(template_path, ctx)
    if used_templater then
      template_lines = lines
    end
  end

  if not template_lines then
    template_lines = {}
    local template_file = io.open(tostring(template_path), "r")
    if template_file then
      local lines = template_file:lines()
      for line in lines do
        local new_lines = M.substitute_template_variables(line, ctx)
        if string.find(new_lines, "[\r\n]") then
          local line_start = 1
          for line_end in util.gfind(new_lines, "[\r\n]") do
            local new_line = string.sub(new_lines, line_start, line_end - 1)
            table.insert(template_lines, new_line)
            line_start = line_end + 1
          end
          local last_line = string.sub(new_lines, line_start)
          if string.len(last_line) > 0 then
            table.insert(template_lines, last_line)
          end
        else
          table.insert(template_lines, new_lines)
        end
      end
      template_file:close()
    else
      error(string.format("Template file '%s' not found", template_path))
    end
  end

  local insert_note = Note.from_lines(template_lines)
  local current_note = api.current_note(buf)
  if not current_note then
    error "Failed to get current note for buffer"
  end

  -- Only round-trip the template's frontmatter through update_frontmatter when
  -- it's actually managed; otherwise leave it in the inserted lines as-is.
  local manage_frontmatter = insert_note.has_frontmatter and current_note:should_save_frontmatter()
  local insert_lines = template_lines
  if manage_frontmatter then
    insert_lines = insert_note:body_lines()
    current_note:merge(insert_note)
  end

  vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, insert_lines)
  local new_cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(win))
  vim.api.nvim_win_set_cursor(0, { new_cursor_row, 0 })

  if manage_frontmatter then
    current_note:update_frontmatter()
  end

  require("obsidian.ui").update(0)

  return Note.from_buffer(buf)
end

--- Check if a template file contains JavaScript (Templater syntax).
--- Looks for Templater-style markers: `<%`, `<%=`, `<%#`, or a leading ` ```js ` code block.
---
---@param template_content string
---@return boolean
M.has_templater_js = function(template_content)
  -- Check for Templater execution markers.
  if template_content:match "<%%" or template_content:match "<%=" or template_content:match "<%%#" then
    return true
  end

  -- Check for a leading ```js code block (within first 10 lines).
  local line_idx = 0
  for line in template_content:gmatch "[^\n]*\n?" do
    line_idx = line_idx + 1
    if line_idx > 10 then
      break
    end
    if line:match "^%s*```js%s*$" then
      return true
    end
  end

  return false
end

--- Read template content from a file.
---
---@param template_path obsidian.Path
---@return string|?
M.read_template_content = function(template_path)
  local file, err = io.open(tostring(template_path), "r")
  if not file then
    log.warn("Failed to read template '%s': %s", template_path, tostring(err))
    return nil
  end
  local content = file:read "*a"
  file:close()
  return content
end

--- Determine if a template should use templater.
--- Reads the template file and checks for JavaScript content.
---
---@param template_name string|obsidian.Path
---@param templates_dir obsidian.Path|?
---@return boolean
M.is_templater_template = function(template_name, templates_dir)
  local template_path = M.resolve_template(template_name, templates_dir)
  local content = M.read_template_content(template_path)
  if not content then
    return false
  end
  return M.has_templater_js(content)
end

--- Run templater on a template file and return the output as a string.
---
---@param template_path obsidian.Path
---@param ctx obsidian.TemplateContext
---@return string|? output
---@return string|? error_message
M.run_templater = function(template_path, ctx)
  local opts = Obsidian.opts.templater
  if not opts or not opts.enabled then
    return nil, "templater is not enabled"
  end

  local cmd = opts.cmd or "templater"
  local args = vim.deepcopy(opts.args or {})
  local pipe_stdin = opts.pipe_stdin ~= false

  -- Build the command arguments.
  if not pipe_stdin then
    table.insert(args, tostring(template_path))
  end

  -- Serialize the context to JSON for templater to consume.
  local context_data = {
    type = ctx.type,
    template_name = tostring(ctx.template_name),
    partial_note = ctx.partial_note and {
      id = ctx.partial_note.id,
      title = ctx.partial_note.title,
      aliases = ctx.partial_note.aliases,
      tags = ctx.partial_note.tags,
      path = ctx.partial_note.path and tostring(ctx.partial_note.path) or nil,
    } or nil,
    destination_path = ctx.destination_path and tostring(ctx.destination_path) or nil,
    templates_dir = ctx.templates_dir and tostring(ctx.templates_dir) or nil,
    date = util.format_date(os.time(), Obsidian.opts.templates.date_format),
    time = util.format_date(os.time(), Obsidian.opts.templates.time_format),
  }

  local context_json = vim.json.encode(context_data)

  -- Build env.
  local env = vim.deepcopy(opts.env or {})
  env.TEMPLATER_CONTEXT = context_json

  local input_data
  if pipe_stdin then
    local content = M.read_template_content(template_path)
    if not content then
      return nil, "failed to read template"
    end
    input_data = content
  end

  log.info("Running templater: %s %s", cmd, table.concat(args, " "))

  local result = vim.system({ cmd, args }, {
    stdin = input_data,
    env = env,
    text = true,
  }):wait()

  if result.code ~= 0 then
    return nil, string.format("templater exited with code %d: %s", result.code, result.stderr or "")
  end

  return result.stdout or "", nil
end

--- Substitute template content using templater.
--- Reads the template, runs templater, and returns the output split into lines.
--- If templater fails, falls back to built-in substitution.
---
---@param template_path obsidian.Path
---@param ctx obsidian.TemplateContext
---@return string[] lines
---@return boolean used_templater
M.substitute_with_templater = function(template_path, ctx)
  local output, err = M.run_templater(template_path, ctx)

  if err then
    log.warn("Templater failed, falling back to built-in substitution: %s", err)
    -- Fall back to built-in.
    local content = M.read_template_content(template_path)
    if content then
      local substituted = M.substitute_template_variables(content, ctx)
      return vim.split(substituted, "\n"), false
    end
    return {}, false
  end

  -- Split output into lines, stripping trailing newline.
  local lines = {}
  for line in output:gmatch "[^\n]*\n?" do
    if line ~= "" then
      table.insert(lines, line)
    end
  end
  -- Remove trailing empty line if present.
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end

  return lines, true
end

return M
