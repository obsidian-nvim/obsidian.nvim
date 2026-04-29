local api = require "obsidian.api"
local Path = require "obsidian.path"
local log = require "obsidian.log"

---@param root obsidian.Path
---@return obsidian.Path[]
local function collect_dirs(root)
  ---@type obsidian.Path[]
  local dirs = { root }

  ---@param dir obsidian.Path
  local function walk(dir)
    for name, kind in vim.fs.dir(tostring(dir)) do
      if kind == "directory" then
        local child = dir / name
        dirs[#dirs + 1] = child
        walk(child)
      end
    end
  end

  walk(root)
  table.sort(dirs, function(a, b)
    return tostring(a) < tostring(b)
  end)

  return dirs
end

---@param data obsidian.CommandArgs
return function(data)
  local note = api.current_note(0)
  if not note then
    log.err "Current buffer is not a markdown note"
    return
  end

  local source_path = Path.buffer(0)
  local source_parent = assert(source_path:parent())
  local source_filename = assert(source_path.name, "current buffer path has no filename")

  local ok = pcall(function()
    source_path:vault_relative_path { strict = true }
  end)
  if not ok then
    log.err("Current note '%s' is outside of the current vault '%s'", source_path, Obsidian.dir)
    return
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  local all_dirs = collect_dirs(Obsidian.dir)
  for _, dir in ipairs(all_dirs) do
    local rel = dir == Obsidian.dir and "/" or assert(dir:vault_relative_path { strict = true })
    entries[#entries + 1] = {
      text = rel,
      filename = tostring(dir),
      user_data = dir,
    }
  end

  local function move_to_dir(entry)
    if not entry then
      log.warn "Move aborted"
      return
    end

    local target_dir = entry.user_data
    if not target_dir then
      log.err("Invalid target directory '%s'", tostring(entry.text))
      return
    end

    if target_dir == source_parent then
      log.info "Note is already in that directory"
      return
    end

    local target_path = target_dir / source_filename
    if target_path:exists() then
      log.err("A note already exists at '%s'", target_path)
      return
    end

    target_dir:mkdir { parents = true }

    vim.cmd.write()
    vim.cmd.saveas(vim.fn.fnameescape(tostring(target_path)))

    vim.fn.delete(tostring(source_path))

    log.info("Moved note to '%s'", target_path)
  end

  if data.args and string.len(data.args) > 0 then
    local target_arg = vim.trim(data.args)
    local target_dir = target_arg == "/" and Obsidian.dir or (Obsidian.dir / target_arg)
    move_to_dir { text = target_arg, user_data = target_dir }
    return
  end

  if Obsidian.picker and Obsidian.picker.pick then
    Obsidian.picker.pick(entries, {
      prompt_title = "Move note to folder",
      callback = move_to_dir,
    })
  else
    vim.ui.select(entries, {
      prompt = "Move note to folder",
      format_item = function(item)
        return item.text
      end,
    }, move_to_dir)
  end
end
