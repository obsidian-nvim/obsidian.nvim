local lsp = vim.lsp
local Note = require "obsidian.note"
local search = require "obsidian.search"
local log = require "obsidian.log"
local api = require "obsidian.api"

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
local function info_from_uri(uri, client)
  local path = vim.uri_to_fname(uri)
  local rel_path = tostring(client:vault_relative_path(path, { strict = true }))

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
local function info_from_id(id, old_path, client)
  local dirname = vim.fs.dirname(old_path)

  local path = vim.fs.joinpath(dirname, id) .. ".md"
  local rel_path = tostring(client:vault_relative_path(path, { strict = true }))

  return {
    rel_path = rel_path,
    path = path,
    id = id,
  }
end

---@param client obsidian.Client
---@param uri string
---@param new_name string
local function rename_note(client, uri, new_name)
  local old = info_from_uri(uri, client)
  local new = info_from_id(new_name, old.path, client)

  local search_lookup = build_search_lookup(old, new)
  local count = 0
  local all_tasks_submitted = false
  local file_map = {}

  search.search_async(
    client.dir,
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
      count = count + 1
    end),
    function(_)
      all_tasks_submitted = true
    end
  )

  vim.lsp.util.rename(old.path, new.path)

  -- Wait for all tasks to get submitted.
  vim.wait(2000, function()
    return all_tasks_submitted
  end, 50, false)

  log.info("renamed " .. count .. " reference(s) across " .. vim.tbl_count(file_map) .. " file(s)")

  -- new file
  local note = Note.from_file(new.path)
  note.id = new.id

  assert(note)
  note:save()

  return note
end

---@param client obsidian.Client
---@param params lsp.RenameParams
return function(client, params, _, _)
  local query = api.parse_cursor_link()

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    log.err(err and err or "failed writing all buffers before renaming, abort")
    return
  end

  if query then
    local notes, note = { client:resolve_note(query) }, nil
    if #notes == 0 then
      log.err("Failed to resolve '%s' to a note", query)
      return
    elseif #notes > 1 then
      log.err("Failed to resolve '%s' to a single note, found %d matches", query, #notes)
      return
    else
      note = notes[1]
    end
    local path = tostring(note.path)
    rename_note(client, vim.uri_from_fname(path), params.newName)
  else
    local note = rename_note(client, params.textDocument.uri, params.newName)
    client:open_note(note)
  end
end
