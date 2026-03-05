--- Handle the "unique" action. Creates a new note with an auto-generated ID.
---@param parsed obsidian.uri.Parsed
local function handle_unique(parsed)
  local ut = require "obsidian.uri.util"
  local Note = require "obsidian.note"

  -- Prefer clipboard, fall back to content param.
  local content = nil
  if parsed.clipboard then
    local clip = vim.fn.getreg "+"
    if clip and clip ~= "" then
      content = clip
    end
  end
  if not content then
    content = parsed.content
  end

  -- id = nil causes note_id_func to auto-generate a zettel ID.
  local note = Note.create {
    should_write = true,
  }

  if content and content ~= "" then
    local lines = vim.split(content, "\n", { plain = true })
    local file_lines = vim.fn.readfile(tostring(note.path))
    vim.list_extend(file_lines, lines)
    vim.fn.writefile(file_lines, tostring(note.path))
  end

  local open_cmd = ut.pane_type_to_open_strategy(parsed.pane_type)
  note:open { sync = true, open_strategy = open_cmd }
end

return handle_unique
