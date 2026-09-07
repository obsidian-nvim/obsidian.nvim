local log = require "obsidian.log"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local ut = require "obsidian.uri.util"

---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_open(parsed)
  if not parsed.file and not parsed.path then
    return ut.success(parsed)
  end

  ---@type obsidian.Path
  local note_path
  if parsed.path then
    note_path = Path.new(parsed.path):resolve()
    if not note_path:is_file() and note_path.suffix == nil then
      note_path = note_path:with_suffix ".md"
    end
  else
    local relative = assert(parsed.file, "file parameter is required")
    note_path = (Obsidian.workspace.root / (relative .. ".md")):resolve()
    if not note_path:is_file() then
      note_path = (Obsidian.workspace.root / relative):resolve()
    end
    if not ut.path_in_current_workspace(note_path) then
      return ut.failure(parsed, ("File escapes the selected workspace: %s"):format(relative))
    end
  end

  if not note_path:is_file() then
    return ut.failure(parsed, ("Note not found: %s"):format(note_path))
  end

  local note = Note.from_file(note_path, { collect_anchor_links = true, collect_blocks = true })
  ---@type integer|?
  local target_line

  if parsed.anchor then
    if vim.startswith(parsed.anchor, "#^") then
      local block_id = parsed.anchor:sub(3)
      local block = note:resolve_block(block_id)
      if block then
        target_line = block.line
      else
        log.warn("Block '^%s' not found in note", block_id)
      end
    elseif vim.startswith(parsed.anchor, "#") then
      local heading = parsed.anchor:sub(2)
      local resolved = note:resolve_anchor_link(heading)
      if resolved then
        target_line = resolved.line
      else
        log.warn("Heading '#%s' not found in note", heading)
      end
    end
  end

  if parsed.append or parsed.prepend then
    ut.write_note(note, parsed, { content = ut.content(parsed) })
  end

  note:open {
    line = target_line,
    sync = true,
    open_strategy = ut.pane_type_to_open_strategy(parsed.pane_type),
  }
  return ut.success(parsed, { note = note })
end

return handle_open
