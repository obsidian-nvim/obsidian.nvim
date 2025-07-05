local lsp = vim.lsp
local Note = require "obsidian.note"
local search = require "obsidian.search"
local log = require "obsidian.log"
local api = require "obsidian.api"
local Path = require "obsidian.path"

-- Search notes on disk for any references to `cur_note_id`.
-- We look for the following forms of references:
-- * '[[cur_note_id]]'
-- * '[[cur_note_id|ALIAS]]'
-- * '[[cur_note_id\|ALIAS]]' (a wiki link within a table)
-- * '[ALIAS](cur_note_id)'
-- And all of the above with relative paths (from the vault root) to the note instead of just the note ID,
-- with and without the ".md" suffix.
-- Another possible form is [[ALIAS]], but we don't change the note's aliases when renaming
-- so those links will still be valid.
local ref_patterns = {
  "[[%s]]", -- wiki
  "[[%s|", -- wiki with alias
  "[[%s\\|", -- wiki link within a table
  "[[%s#", -- wiki with heading
  "](%s)", -- markdown
  "](%s#", -- markdown with heading
}

---@class obsidian.lsp.note_info
---@field id string
---@field rel_path string
---@field path string

local function build_search_lookup(old, new)
  local replace_lookup = {}

  for _, pat in ipairs(ref_patterns) do
    replace_lookup[pat:format(old.id)] = pat:format(new.id)
    replace_lookup[pat:format(old.rel_path)] = pat:format(new.rel_path)
    replace_lookup[pat:format(old.rel_path:sub(1, -4))] = pat:format(new.rel_path:sub(1, -4))
  end

  return replace_lookup, vim.tbl_keys(replace_lookup)
end

---Return file info from uri
---
---@return obsidian.lsp.note_info
local function info_from_uri(uri)
  local path = vim.uri_to_fname(uri)
  local rel_path = Path.new(path):vault_relative_path { strict = true }

  local note = Note.from_file(path)
  local id = tostring(note.id)

  return {
    rel_path = rel_path,
    path = path,
    id = id,
  }
end

--- TODO: should move to other dirs, with new name like ../newname
--- TODO: note id func?

---Return file info from id and old path
---
---@return obsidian.lsp.note_info
local function info_from_id(id, old_path)
  local dirname = vim.fs.dirname(old_path)

  local path = vim.fs.joinpath(dirname, id) .. ".md"
  local rel_path = Path.new(path):vault_relative_path { strict = true }

  return {
    rel_path = rel_path,
    path = path,
    id = id,
  }
end

---@param uri string
---@param new_name string
---@param target obsidian.Note
local function rename_note(uri, new_name, target)
  local old = info_from_uri(uri)
  local new = info_from_id(new_name, old.path)

  local search_lookup = build_search_lookup(old, new)
  local count = 0
  local all_tasks_submitted = false
  local file_map = {}
  local buf_list = {}

  search.search_async(
    Obsidian.dir,
    vim.tbl_keys(search_lookup),
    { fixed_strings = true },
    vim.schedule_wrap(function(match)
      local file = match.path.text
      file_map[file] = true
      local line = match.line_number - 1
      local start, _end = match.submatches[1].start, match.submatches[1]["end"]
      local matched = match.submatches[1].match.text
      local edit = {
        documentChanges = {
          {
            textDocument = {
              uri = vim.uri_from_fname(file),
            },
            edits = {
              {
                range = {
                  start = { line = line, character = start },
                  ["end"] = { line = line, character = _end },
                },
                newText = search_lookup[matched],
              },
            },
          },
        },
      }
      lsp.util.apply_workspace_edit(edit, "utf-8")
      local buf = vim.fn.bufnr(file)
      buf_list[#buf_list + 1] = buf
      count = count + 1
    end),
    function(_)
      all_tasks_submitted = true
    end
  )

  vim.lsp.util.rename(old.path, new.path)

  if not target.bufnr then
    target.bufnr = vim.fn.bufnr(new.path)
  end

  -- Wait for all tasks to get submitted.
  vim.wait(2000, function()
    return all_tasks_submitted
  end, 50, false)

  log.info("renamed " .. count .. " reference(s) across " .. vim.tbl_count(file_map) .. " file(s)")

  target.id = new.id
  target.path = Path.new(new.path)
  target:save_to_buffer { bufnr = target.bufnr }

  -- so that file with renamed refs are displaying correctly
  for _, buf in ipairs(buf_list) do
    vim.bo[buf].filetype = "markdown"
  end

  return target
end

local function validate_new_name(name)
  for path in api.iter_files() do
    local base_as_id = vim.fs.basename(path):sub(1, -4)
    if name == base_as_id then
      return false
    end
    local note = Note.from_file(path)
    if note then
      if name == note.id then
        return false
      end
    end
  end
  return true
end

---@param params lsp.RenameParams
return function(params, _, _)
  local new_name = params.newName

  if not validate_new_name(new_name) then
    log.warn "Invalid rename id, note with the same id/filename already exists"
    return
  end

  local query = api.parse_cursor_link()

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    log.err(err and err or "failed writing all buffers before renaming, abort")
    return
  end

  local client = require("obsidian").get_client() -- HACK:

  if query then
    local notes = { client:resolve_note(query) }
    if #notes == 0 then
      log.err("Failed to resolve '%s' to a note", query)
      return
    elseif #notes > 1 then
      log.err("Failed to resolve '%s' to a single note, found %d matches", query, #notes)
      return
    end
    local note = notes[1]
    local uri = vim.uri_from_fname(tostring(note.path))
    rename_note(uri, new_name, note)
  else
    local uri = params.textDocument.uri
    local note = assert(api.current_note(0))
    local new_note = rename_note(uri, new_name, note)
    Note.open(new_note)
  end
end
