local ut = require "obsidian.uri.util"

--- Handle the "new" action.
---@param parsed obsidian.uri.Parsed
local function handle_new(parsed)
  local Note = require "obsidian.note"
  local Path = require "obsidian.path"

  -- Determine the note identity.
  local id = parsed.name or parsed.file
  local dir = nil

  if parsed.path then
    -- Absolute path: derive dir and id from it.
    local p = Path.new(parsed.path)
    dir = p:parent()
    id = tostring(p.stem)
  elseif parsed.file then
    -- file is a vault-absolute path like "path/to/note".
    -- The id already contains path components which Note._resolve_id_path handles.
    id = parsed.file
  end

  -- Determine content.
  local content = parsed.content
  -- TODO: further clipboard support
  if parsed.clipboard then
    content = vim.fn.getreg "+"
  end

  local note = Note.create {
    id = id,
    dir = dir,
    should_write = true,
  }

  -- Write content if provided.
  if content and content ~= "" then
    local lines = vim.split(content, "\n", { plain = true })
    local file_lines = vim.fn.readfile(tostring(note.path))
    -- Append content after the existing template content.
    vim.list_extend(file_lines, lines)
    vim.fn.writefile(file_lines, tostring(note.path))
  end

  if not parsed.silent then
    local open_cmd = ut.pane_type_to_open_strategy(parsed.pane_type)
    note:open {
      sync = true,
      open_strategy = open_cmd,
    }
  end
end

return handle_new
