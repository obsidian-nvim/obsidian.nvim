local obsidian = require "obisidian"
local Note = obsidian.note
local search = obsidian.search
local log = obsidian.log
local api = obsidian.api
local util = obsidian.util
local Path = obsidian.path
local lsp = vim.lsp

-- TODO: all the backlinks patterns checked
-- local raw_refs = {
--   tostring(note.id),
--   note_path.name,
--   note_path.stem,
--   rel_path,
--   rel_path and rel_path:gsub(".md", "") or nil,
-- }

-- TODO: use hanlder, to have LSP rename plugin integration

-- TODO: note:rename(self, new_name, callback)

----@param old_path string
---@param note obsidian.Note
---@param new_name string
local function rename_note(note, new_name)
  local old_path = tostring(note.path)
  local old_id = note.id

  local new_id = new_name
  local new_path = vim.fs.joinpath(vim.fs.dirname(old_path), new_id) .. ".md" -- TODO: resolve relative paths like ../new_name.md

  local count = 0
  local path_lookup = {}
  local buf_list = {}

  local matches = note:backlinks {}

  local documentChanges = {}

  for _, match in ipairs(matches) do
    local match_path = tostring(match.path)
    local offset_st, offset_ed = string.find(match.text, old_id)
    if offset_st and offset_ed then
      local replace_st, replace_ed = offset_st + match.start - 1, offset_ed + match.start

      documentChanges[#documentChanges + 1] = {
        textDocument = {
          uri = vim.uri_from_fname(match_path),
          version = vim.NIL,
        },
        edits = {
          {
            range = {
              start = { line = match.line - 1, character = replace_st },
              ["end"] = { line = match.line - 1, character = replace_ed },
            },
            newText = new_id,
          },
        },
      }
      count = count + 1
      buf_list[#buf_list + 1] = vim.fn.bufnr(match_path, true)
      path_lookup[match_path] = true
    end
  end

  ---@type lsp.WorkspaceEdit
  local edit = { documentChanges = documentChanges }
  lsp.util.apply_workspace_edit(edit, "utf-8")

  lsp.util.rename(old_path, new_path)

  if not note.bufnr then
    note.bufnr = vim.fn.bufnr(new_path, true)
  end

  -- so that file with renamed refs are displaying correctly
  for _, buf in ipairs(buf_list) do
    vim.bo[buf].filetype = "markdown"
  end

  note.id = new_id
  note.path = Path.new(new_path)
  note:save_to_buffer { bufnr = note.bufnr }

  log.info("renamed " .. count .. " reference(s) across " .. vim.tbl_count(path_lookup) .. " file(s)")

  return note
end

local function validate_new_name(name)
  for path in api.dir(Obsidian.dir) do
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

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    return log.err(err and err or "failed writing all buffers before renaming, abort")
  end

  if not validate_new_name(new_name) then
    return log.warn "Invalid rename id, note with the same id/filename already exists"
  end

  local cur_link = api.cursor_link()

  if cur_link then
    local loc = util.parse_link(cur_link, { strip = true })
    assert(loc, "wrong link format")
    local notes = search.resolve_note(loc)
    if vim.tbl_isempty(notes) then
      return
    end
    local note = notes[1]
    rename_note(note, new_name)
  else
    local uri = params.textDocument.uri
    local note = assert(api.current_note(0))
    local path = vim.uri_to_fname(uri)
    rename_note(note, new_name)
  end
end
