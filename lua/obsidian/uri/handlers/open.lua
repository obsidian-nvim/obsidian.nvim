local log = require "obsidian.log"
local ut = require "obsidian.uri.util"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local api = require "obsidian.api"

--- Handle the "open" action.
---@param parsed obsidian.uri.Parsed
local function handle_open(parsed)
  local file_path = parsed.file or parsed.path
  if not file_path then
    -- Just open/switch to the vault, nothing more to do.
    log.info("Switched to vault '%s'", Obsidian.workspace.name)
    return
  end

  ---@type obsidian.Path
  local note_path
  if parsed.path then
    -- Absolute path: use directly.
    note_path = Path.new(parsed.path)
  else
    -- Relative to vault root. Try with and without .md extension.
    note_path = Obsidian.dir / (parsed.file .. ".md")
    if not note_path:is_file() then
      note_path = Obsidian.dir / parsed.file
    end
  end

  if not note_path:is_file() then
    log.err("Note not found: %s", tostring(note_path))
    return
  end

  local open_cmd = ut.pane_type_to_open_strategy(parsed.pane_type) or api.get_open_strategy(Obsidian.opts.open_notes_in)

  -- Open the note.
  local note = Note.from_file(note_path, { collect_anchor_links = true, collect_blocks = true })

  ---@type integer|?
  local target_line

  -- Resolve anchor or block reference.
  if parsed.anchor then
    local anchor = parsed.anchor
    if anchor:sub(1, 2) == "#^" then
      -- Block reference.
      local block_id = anchor:sub(3)
      local block = note:resolve_block(block_id)
      if block then
        target_line = block[1]
      else
        log.warn("Block '^%s' not found in note", block_id)
      end
    elseif anchor:sub(1, 1) == "#" then
      -- Heading anchor.
      local heading = anchor:sub(2)
      local resolved = note:resolve_anchor_link(heading)
      if resolved then
        target_line = resolved.line
      else
        log.warn("Heading '#%s' not found in note", heading)
      end
    end
  end

  api.open_note({
    filename = tostring(note_path),
    lnum = target_line,
  }, open_cmd)
end

return handle_open
