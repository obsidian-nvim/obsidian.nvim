local lsp = vim.lsp
local Note = require "obsidian.note"
local search = require "obsidian.search"
local log = require "obsidian.log"
local api = require "obsidian.api"
local util = require "obsidian.util"
local Path = require "obsidian.path"

--- TODO: should move to other dirs, with new name like ../newname
--- TODO: note id func?

---@param old_path string
---@param new_name string
---@param target obsidian.Note
local function rename_note(old_path, new_name, target)
  local old_id = Note.from_file(old_path).id
  local new_id = new_name
  local new_path = vim.fs.joinpath(vim.fs.dirname(old_path), new_id) .. ".md" -- TODO: resolve relative paths like ../new_name.md

  local count = 0
  local path_lookup = {}
  local buf_list = {}

  local matches = target:backlinks {}

  local documentChanges = {}

  for _, match in ipairs(matches) do
    local match_path = tostring(match.path)
    local offset_st, offset_ed = string.find(match.text, old_id)
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
    buf_list[#buf_list + 1] = vim.fn.bufnr(match_path)
    path_lookup[match_path] = true
  end

  ---@type lsp.WorkspaceEdit
  local edit = { documentChanges = documentChanges }
  lsp.util.apply_workspace_edit(edit, "utf-8")

  lsp.util.rename(old_path, new_path)

  if not target.bufnr then
    target.bufnr = vim.fn.bufnr(new_path, true)
  end

  -- so that file with renamed refs are displaying correctly
  for _, buf in ipairs(buf_list) do
    vim.bo[buf].filetype = "markdown"
  end

  target.id = new_id
  target.path = Path.new(new_path)
  target:save_to_buffer { bufnr = target.bufnr }

  log.info("renamed " .. count .. " reference(s) across " .. vim.tbl_count(path_lookup) .. " file(s)")

  return target
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
    local loc = util.parse_link(cur_link)
    assert(loc, "wrong link format")
    loc = util.strip_anchor_links(loc)
    loc = util.strip_block_links(loc)
    local note = search.resolve_note(loc)
    if not note then
      return
    end
    rename_note(tostring(note.path), new_name, note)
  else
    local uri = params.textDocument.uri
    local note = assert(api.current_note(0))
    local path = vim.uri_to_fname(uri)
    local new_note = rename_note(path, new_name, note)
    new_note:open()
  end
end
