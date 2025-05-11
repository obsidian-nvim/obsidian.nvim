local Note = require "obsidian.note"
local subst = require "obsidian.subst"
local util = require "obsidian.util"

local M = {}

--- Clone template to a new note.
---
---@param ctx obsidian.SubstitutionContext
---
---@return obsidian.Note
M.clone_template = function(ctx)
  ctx = subst.assert_valid_context(ctx, "clone_template")

  ctx.target_note.path:mkdir { parents = true, exist_ok = true }
  local template_file, read_err = io.open(tostring(ctx.template), "r")
  if not template_file then
    error(string.format("Unable to read template at '%s': %s", ctx.template, tostring(read_err)))
  end

  local note_file, write_err = io.open(tostring(ctx.target_note.path), "w")
  if not note_file then
    error(string.format("Unable to write note at '%s': %s", ctx.target_note.path, tostring(write_err)))
  end

  for line in template_file:lines "L" do
    line = subst.substitute_template_variables(line, ctx)
    note_file:write(line)
  end

  assert(template_file:close())
  assert(note_file:close())

  local new_note = Note.from_file(ctx.target_note.path)

  -- Transfer fields from `opts.note`.
  new_note.id = ctx.target_note.id
  if new_note.title == nil then
    new_note.title = ctx.target_note.title
  end
  for _, alias in ipairs(ctx.target_note.aliases) do
    new_note:add_alias(alias)
  end
  for _, tag in ipairs(ctx.target_note.tags) do
    new_note:add_tag(tag)
  end

  return new_note
end

---Insert a template at the given location.
---
---@param ctx obsidian.SubstitutionContext
---
---@return obsidian.Note
M.insert_template = function(ctx)
  ctx = subst.assert_valid_context(ctx, "insert_template")

  local buf, win, row, _ = unpack(ctx.target_location)
  local template_file = io.open(tostring(ctx.template), "r")

  local insert_lines = {}
  if template_file then
    local lines = template_file:lines()
    for line in lines do
      local new_lines = subst.substitute_template_variables(line, ctx)
      if string.find(new_lines, "[\r\n]") then
        local line_start = 1
        for line_end in util.gfind(new_lines, "[\r\n]") do
          local new_line = string.sub(new_lines, line_start, line_end - 1)
          table.insert(insert_lines, new_line)
          line_start = line_end + 1
        end
        local last_line = string.sub(new_lines, line_start)
        if string.len(last_line) > 0 then
          table.insert(insert_lines, last_line)
        end
      else
        table.insert(insert_lines, new_lines)
      end
    end
    template_file:close()
  else
    error(string.format("Template file '%s' not found", ctx.template))
  end

  vim.api.nvim_buf_set_lines(buf, row - 1, row - 1, false, insert_lines)
  local new_cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(win))
  vim.api.nvim_win_set_cursor(0, { new_cursor_row, 0 })

  ctx.client:update_ui(0)

  return Note.from_buffer(buf)
end

return M
