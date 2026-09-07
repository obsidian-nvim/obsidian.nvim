local Note = require "obsidian.note"
local Path = require "obsidian.path"
local ut = require "obsidian.uri.util"

---@param parsed obsidian.uri.Parsed
---@return obsidian.Path|nil
---@return string|nil
local function target_path(parsed)
  if parsed.path then
    local path = Path.new(parsed.path)
    if not path:is_absolute() then
      return nil, "The path parameter must be absolute"
    end
    path = path:resolve()
    if path.suffix == nil then
      path = path:with_suffix ".md"
    end
    if not ut.path_in_current_workspace(path) then
      return nil, ("Path is not inside the selected workspace: %s"):format(path)
    end
    return path, nil
  elseif parsed.file then
    local path = (Obsidian.workspace.root / parsed.file):resolve()
    if path.suffix == nil then
      path = path:with_suffix ".md"
    end
    if not ut.path_in_current_workspace(path) then
      return nil, ("File escapes the selected workspace: %s"):format(parsed.file)
    end
    return path, nil
  end

  ---@diagnostic disable-next-line: access-invisible
  local _, path = Note._resolve_id_path({
    id = parsed.name,
    verbatim = parsed.name ~= nil,
    template = Obsidian.opts.note.template,
  }, false)
  if not ut.path_in_current_workspace(path) then
    return nil, ("New-note path escapes the selected workspace: %s"):format(path)
  end
  return path, nil
end

--- Handle the `new` action.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
local function handle_new(parsed)
  local path, err = target_path(parsed)
  if not path then
    return ut.failure(parsed, assert(err, "target path error is required"))
  end

  local note = ut.note_at_path(path, "uri", Obsidian.opts.note.template)
  ut.write_note(note, parsed, { content = ut.content(parsed) })

  if not parsed.silent then
    note:open {
      sync = true,
      open_strategy = ut.pane_type_to_open_strategy(parsed.pane_type),
    }
  end
  return ut.success(parsed, { note = note, silent = parsed.silent })
end

return handle_new
