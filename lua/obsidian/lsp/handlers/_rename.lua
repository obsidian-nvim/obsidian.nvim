local M = {}

local obsidian = require "obsidian"
local Note = obsidian.Note
local Path = obsidian.Path
local log = obsidian.log
local api = obsidian.api

---@param name string
---@return boolean
M.validate = function(name)
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

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

-- TODO: note:rename(self, new_name, callback)

---@param note obsidian.Note
---@param new_name string
---@param callback function -- TODO:
M.rename = function(note, new_name, callback)
  local old_refs = note:get_reference_paths()
  local old_path = tostring(note.path)

  local new_path = vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md" -- TODO: resolve relative paths like ../new_name.md

  if old_path == new_path then
    return callback(nil, nil)
  end

  local count = 0
  local path_lookup = {}
  local buf_list = {}

  local matches = note:backlinks {}

  local documentChanges = {}

  for _, match in ipairs(matches) do
    local match_path = tostring(match.path)

    for _, ref in ipairs(old_refs) do
      local offset_st, offset_ed = string.find(match.text, ref)
      if offset_st and offset_ed then
        local replace_st, replace_ed = offset_st + match.start - 1, offset_ed + match.start

        documentChanges[#documentChanges + 1] = {
          textDocument = {
            uri = vim.uri_from_fname(match_path),
            version = has_nvim_0_12 and vim.NIL or nil,
          },
          edits = {
            {
              range = {
                start = { line = match.line - 1, character = replace_st },
                ["end"] = { line = match.line - 1, character = replace_ed },
              },
              newText = new_name,
            },
          },
        }
        count = count + 1
        buf_list[#buf_list + 1] = vim.fn.bufnr(match_path, true)
        path_lookup[match_path] = true
      end
    end
  end

  ---@type lsp.RenameFile
  local rename_file = {
    kind = "rename",
    oldUri = vim.uri_from_fname(old_path),
    newUri = vim.uri_from_fname(new_path),
    options = {}, -- TODO:
  }

  documentChanges[#documentChanges + 1] = rename_file

  local edit = { documentChanges = documentChanges }

  callback(nil, edit)

  if not note.bufnr then
    note.bufnr = vim.fn.bufnr(new_path, true)
  end

  -- so that file with renamed refs are displaying correctly
  for _, buf in ipairs(buf_list) do
    vim.bo[buf].filetype = "markdown"
  end

  note.id = new_name
  note.path = Path.new(new_path)
  note:save_to_buffer { bufnr = note.bufnr }

  log.info("renamed " .. count .. " reference(s) across " .. vim.tbl_count(path_lookup) .. " file(s)")

  return note
end

return M
