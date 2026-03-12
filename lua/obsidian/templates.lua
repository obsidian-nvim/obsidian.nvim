local Path = require "obsidian.path"
local Note = require "obsidian.note"
local api = require "obsidian.api"

local M = {}

---@param src string
---@param chunk_name string
---@param env table
---@return function|nil
---@return string|nil
local function load_with_env(src, chunk_name, env)
  local fn, err = loadstring(src, chunk_name)
  if not fn then
    return nil, err
  end

  setfenv(fn, env)
  return fn, nil
end

---@param text string
---@param start_idx integer
---@return integer|nil
---@return integer|nil
local function find_lua_block_close(text, start_idx)
  local line_start = start_idx

  while line_start <= #text + 1 do
    local newline_idx = string.find(text, "\n", line_start, true)
    local line_end = newline_idx and (newline_idx - 1) or #text
    local line = string.sub(text, line_start, line_end)

    if string.match(line, "^%s*}}%s*$") then
      return line_start, line_end
    end

    if newline_idx == nil then
      break
    end

    line_start = newline_idx + 1
  end

  return nil, nil
end

---@param text string
---@return string[]
local function split_lines(text)
  local normalized = string.gsub(text, "\r\n", "\n")
  local lines = vim.split(normalized, "\n", { plain = true })
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

---@param methods table<string, string|fun(ctx: obsidian.TemplateContext, suffix: string|?):string|?>
---@param ctx obsidian.TemplateContext
---@param suffix string|?
---@return table
local function make_template_env(methods, ctx, suffix)
  local env = {
    ctx = ctx,
    tp = ctx.partial_note,
  }

  return setmetatable(env, {
    __index = function(_, key)
      local ctx_value = rawget(ctx, key)
      if ctx_value ~= nil then
        return ctx_value
      end

      local subst = methods[key]
      if subst ~= nil then
        if type(subst) == "string" then
          return subst
        else
          return subst(ctx, suffix)
        end
      end

      return _G[key]
    end,
  })
end

---@param methods table<string, string|fun(ctx: obsidian.TemplateContext, suffix: string|?):string|?>
---@param ctx obsidian.TemplateContext
---@param expr string
---@return string
local function eval_lua_expression(methods, ctx, expr)
  local env = make_template_env(methods, ctx)
  local chunk, load_err = load_with_env("return " .. expr, "template expression", env)
  if not chunk then
    return string.format("[template error: %s]", tostring(load_err))
  end

  local ok, run_err = pcall(chunk)
  if not ok then
    return string.format("[template error: %s]", tostring(run_err))
  end

  return tostring(run_err)
end

---@param methods table<string, string|fun(ctx: obsidian.TemplateContext, suffix: string|?):string|?>
---@param ctx obsidian.TemplateContext
---@param code string
---@param indent string
---@return string
local function eval_lua_block(methods, ctx, code, indent)
  local buffer = {}

  local env = make_template_env(methods, ctx)
  env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      parts[i] = tostring(select(i, ...))
    end
    table.insert(buffer, table.concat(parts, " "))
  end

  local chunk, load_err = load_with_env(code, "template lua block", env)
  if not chunk then
    return string.format("[template error: %s]", tostring(load_err))
  end

  local ok, run_err = pcall(chunk)
  if not ok then
    return string.format("[template error: %s]", tostring(run_err))
  end

  if #buffer == 0 then
    return ""
  end

  local lines = {}
  for _, line in ipairs(buffer) do
    table.insert(lines, indent .. line)
  end

  return table.concat(lines, "\n")
end

---@param methods table<string, string|fun(ctx: obsidian.TemplateContext, suffix: string|?):string|?>
---@param ctx obsidian.TemplateContext
---@param token string
---@return string
local function resolve_variable_token(methods, ctx, token)
  local key, suffix = string.match(token, "^([%a_][%w_]*):(.+)$")
  if key and methods[key] ~= nil and type(methods[key]) == "function" then
    local out = methods[key](ctx, vim.trim(suffix))
    return out ~= nil and tostring(out) or ""
  end

  local subst = methods[token]
  if subst ~= nil then
    if type(subst) == "string" then
      return subst
    else
      local out = subst(ctx)
      return out ~= nil and tostring(out) or ""
    end
  end

  if string.match(token, "^[%a_][%w_]*$") then
    local value = api.input(string.format("Enter value for '%s' (<cr> to skip): ", token))
    if value and string.len(value) > 0 then
      return value
    end
  end

  return "{{" .. token .. "}}"
end

---@param text string
---@param methods table<string, string|fun(ctx: obsidian.TemplateContext, suffix: string|?):string|?>
---@param ctx obsidian.TemplateContext
---@return string
local function render_template(text, methods, ctx)
  local out = {}
  local i = 1

  while i <= #text do
    local open_start, open_end = string.find(text, "{{", i, true)
    if not open_start then
      table.insert(out, string.sub(text, i))
      break
    end

    table.insert(out, string.sub(text, i, open_start - 1))

    local token_start = open_end + 1
    local is_lua_block = string.match(string.sub(text, token_start), "^lua[ \t]*\r?\n") ~= nil
    if is_lua_block then
      local _, header_end_rel = string.find(string.sub(text, token_start), "^lua[ \t]*\r?\n")
      local block_start = token_start + header_end_rel
      local close_line_start, close_line_end = find_lua_block_close(text, block_start)
      if close_line_start == nil or close_line_end == nil then
        table.insert(out, "[template error: missing closing delimiter for lua block]")
        break
      end

      local before_open = string.sub(text, 1, open_start - 1)
      local prev_newline = string.match(before_open, ".*()\n")
      local indent = prev_newline and string.sub(before_open, prev_newline + 1) or before_open
      if string.match(indent, "^%s*$") == nil then
        indent = ""
      elseif #indent > 0 and #out > 0 and vim.endswith(out[#out], indent) then
        out[#out] = string.sub(out[#out], 1, #out[#out] - #indent)
      end

      local code = string.sub(text, block_start, close_line_start - 1)
      table.insert(out, eval_lua_block(methods, ctx, code, indent))

      i = close_line_end + 1
      if string.sub(text, i, i) == "\n" then
        i = i + 1
      end
    else
      local close_start, close_end = string.find(text, "}}", token_start, true)
      if not close_start then
        table.insert(out, string.sub(text, open_start))
        break
      end

      local token = vim.trim(string.sub(text, token_start, close_start - 1))
      if vim.startswith(token, "=") then
        table.insert(out, eval_lua_expression(methods, ctx, vim.trim(string.sub(token, 2))))
      else
        table.insert(out, resolve_variable_token(methods, ctx, token))
      end

      i = close_end + 1
    end
  end

  return table.concat(out, "")
end

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

  return render_template(text, methods, ctx)
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

  local template_file, read_err = io.open(tostring(template_path), "r")
  if not template_file then
    error(string.format("Unable to read template at '%s': %s", template_path, tostring(read_err)))
  end

  local template_content = template_file:read "*a"
  assert(template_file:close())

  local rendered_content = M.substitute_template_variables(template_content, ctx)

  local note_file, write_err = io.open(tostring(note_path), "w")
  if not note_file then
    error(string.format("Unable to write note at '%s': %s", note_path, tostring(write_err)))
  end

  note_file:write(rendered_content)
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

  ---@type string[]
  local template_lines = {}
  local template_file = io.open(tostring(template_path), "r")
  if template_file then
    local template_content = template_file:read "*a"
    local rendered_content = M.substitute_template_variables(template_content, ctx)
    template_lines = split_lines(rendered_content)
    template_file:close()
  else
    error(string.format("Template file '%s' not found", template_path))
  end

  local insert_note = Note.from_lines(template_lines)
  local current_note = api.current_note(buf)
  if not current_note then
    error "Failed to get current note for buffer"
  end

  local insert_lines = template_lines
  if insert_note.has_frontmatter then
    insert_lines = insert_note:body_lines()
    current_note:merge(insert_note)
  end

  vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, insert_lines)
  local new_cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(win))
  vim.api.nvim_win_set_cursor(0, { new_cursor_row, 0 })

  if insert_note.has_frontmatter then
    current_note:update_frontmatter()
  end

  require("obsidian.ui").update(0)

  return Note.from_buffer(buf)
end

return M
