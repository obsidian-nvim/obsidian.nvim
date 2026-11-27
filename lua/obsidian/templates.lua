local Path = require "obsidian.path"
local Note = require "obsidian.note"
local util = require "obsidian.util"
local api = require "obsidian.api"

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
---@param ctx obsidian.templates.Context
---
---@return string
M.substitute_template_variables = function(text, ctx)
  local methods = vim.deepcopy(Obsidian.opts.templates.substitutions or {})

  local result = {}
  local pos = 1
  while pos <= #text do
    local open = text:find("{{", pos, true)
    local escaped_open = text:find("\\{{", pos, true)
    local escaped_close = text:find("\\}}", pos, true)
    local escaped = escaped_open and (not escaped_close or escaped_open < escaped_close) and escaped_open
      or escaped_close
    if escaped and (not open or escaped <= open) then
      result[#result + 1] = text:sub(pos, escaped - 1)
      result[#result + 1] = text:sub(escaped + 1, escaped + 2)
      pos = escaped + 3
    elseif open then
      local close = text:find("}}", open + 2, true)
      if not close or close == open + 2 then
        result[#result + 1] = text:sub(pos, open + 1)
        pos = open + 2
      else
        result[#result + 1] = text:sub(pos, open - 1)
        local raw = text:sub(open, close + 1)
        local key = vim.trim(text:sub(open + 2, close - 1))
        local subst = methods[key]
        local suffix
        if subst == nil then
          local name, arg = key:match "^([^:]+):(.*)$"
          if name and type(methods[name]) == "function" then
            subst = methods[name]
            suffix = vim.trim(arg or "")
          end
        end
        local value
        if type(subst) == "function" then
          value = subst(ctx, suffix)
        elseif type(subst) == "string" then
          value = subst
        else
          value = api.input(string.format("Enter value for '%s' (<cr> to skip): ", key))
        end
        result[#result + 1] = value and #value > 0 and value or raw
        pos = close + 2
      end
    else
      result[#result + 1] = text:sub(pos)
      break
    end
  end
  return table.concat(result)
end

--- Clone template to a new note.
---
---@param ctx obsidian.templates.CloneContext
---
---@return obsidian.Note
M.clone_template = function(ctx)
  local note_path = Path.new(ctx.destination_path)
  assert(note_path:parent()):mkdir { parents = true, exist_ok = true }

  local template_path = M.resolve_template(ctx.template_name, ctx.templates_dir)

  local template_file, read_err = io.open(tostring(template_path), "r")
  if not template_file then
    error(string.format("Unable to read template at '%s': %s", template_path, tostring(read_err)))
  end

  local note_file, write_err = io.open(tostring(note_path), "w")
  if not note_file then
    error(string.format("Unable to write note at '%s': %s", note_path, tostring(write_err)))
  end

  for line in template_file:lines "L" do
    ---@cast line string
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
---@param ctx obsidian.templates.InsertContext
---
---@return obsidian.Note
M.insert_template = function(ctx)
  local buf, win, row, _ = unpack(ctx.location)
  if ctx.partial_note == nil then
    ctx.partial_note = Note.from_buffer(buf)
  end

  local template_path = M.resolve_template(ctx.template_name, ctx.templates_dir)

  ---@type string[]
  local template_lines = {}
  local template_file = io.open(tostring(template_path), "r")
  if template_file then
    local lines = template_file:lines()
    for line in lines do
      ---@cast line string
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

return M
