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
    path = Path.new(path)
    if name == path.stem then
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

local function build_search_note(note, old_path)
  local search_note = vim.tbl_extend("force", {}, note, { path = Path.new(old_path) })
  return setmetatable(search_note, getmetatable(note))
end

---@param note obsidian.Note
---@param new_name string
---@param opts? { old_path: string|?, new_path: string|?, include_file_rename: boolean|? }
---@return lsp.WorkspaceEdit|?, { count: integer, path_lookup: table<string, boolean>, buf_list: integer[], old_path: string, new_path: string }
M.build_edit = function(note, new_name, opts)
  opts = opts or {}

  local old_path = opts.old_path or tostring(note.path)
  local new_path = opts.new_path or (vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md")
  local include_file_rename = opts.include_file_rename ~= false
  local old_refs = build_search_note(note, old_path):get_reference_paths()

  -- Sort refs by length (longest first) to match most specific reference first
  table.sort(old_refs, function(a, b)
    return #a > #b
  end)

  local count = 0
  local path_lookup = {}
  local buf_list = {}
  local matches = build_search_note(note, old_path):backlinks {}
  local documentChanges = {}

  -- Track which lines we've already processed to avoid duplicates
  local processed_lines = {}

  for _, match in ipairs(matches) do
    local match_path = tostring(match.path)
    local line_key = match_path .. ":" .. match.line

    -- Skip if we've already processed this line
    if not processed_lines[line_key] then
      processed_lines[line_key] = true

      -- Find ALL occurrences of refs in this line
      local line_edits = {}

      for _, ref in ipairs(old_refs) do
        local search_start = 1
        while true do
          local offset_st, offset_ed = string.find(match.text, ref, search_start, true)
          if not offset_st then
            break
          end

          local new_text = new_name
          if vim.endswith(ref, ".md") then
            new_text = new_name .. ".md"
          end

          -- Check if this position overlaps with an already found edit (longer ref takes priority)
          local dominated = false
          for _, existing in ipairs(line_edits) do
            if offset_st >= existing.start_1idx and offset_ed <= existing.end_1idx then
              -- This match is inside an existing longer match, skip it
              dominated = true
              break
            end
          end

          if not dominated then
            line_edits[#line_edits + 1] = {
              start_1idx = offset_st,
              end_1idx = offset_ed,
              -- LSP with utf-8 offset_encoding expects byte positions (0-indexed)
              replace_st = offset_st - 1,
              replace_ed = offset_ed,
              new_text = new_text,
            }
          end

          search_start = offset_ed + 1
        end
      end

      -- Sort line_edits by position descending (right to left) so edits don't affect each other's positions
      table.sort(line_edits, function(a, b)
        return a.start_1idx > b.start_1idx
      end)

      -- Collect all edits for this file
      if #line_edits > 0 then
        local edits_for_line = {}
        for _, edit_info in ipairs(line_edits) do
          edits_for_line[#edits_for_line + 1] = {
            range = {
              start = { line = match.line - 1, character = edit_info.replace_st },
              ["end"] = { line = match.line - 1, character = edit_info.replace_ed },
            },
            newText = edit_info.new_text,
          }
          count = count + 1
        end

        documentChanges[#documentChanges + 1] = {
          textDocument = {
            uri = vim.uri_from_fname(match_path),
            version = has_nvim_0_12 and vim.NIL or nil,
          },
          edits = edits_for_line,
        }

        buf_list[#buf_list + 1] = vim.fn.bufnr(match_path, true)
        path_lookup[match_path] = true
      end
    end
  end

  if include_file_rename and old_path ~= new_path then
    documentChanges[#documentChanges + 1] = {
      kind = "rename",
      oldUri = vim.uri_from_fname(old_path),
      newUri = vim.uri_from_fname(new_path),
      options = {},
    }
  end

  local edit = #documentChanges > 0 and { documentChanges = documentChanges } or nil

  return edit,
    {
      count = count,
      path_lookup = path_lookup,
      buf_list = buf_list,
      old_path = old_path,
      new_path = new_path,
    }
end

---@param note obsidian.Note
---@param new_name string
---@param callback function -- TODO:
---@param opts? { old_path: string|?, new_path: string|?, include_file_rename: boolean|? }
M.rename = function(note, new_name, callback, opts)
  opts = opts or {}

  local edit, meta = M.build_edit(note, new_name, opts)
  callback(nil, edit)

  local current_file = vim.api.nvim_buf_get_name(0)
  local new_path = meta.new_path
  local old_path = meta.old_path
  local buf_list = meta.buf_list

  vim.schedule(function()
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

    -- Reload buffer to show updated backlinks
    -- Save all modified buffers (including files with updated refs)
    vim.cmd "silent! wall"
    -- If we were editing the renamed file, switch to its new path
    -- Otherwise stay in the current file (e.g., when renaming from a referencing note)
    if current_file == old_path then
      vim.cmd("edit " .. vim.fn.fnameescape(new_path))
    else
      vim.cmd("edit " .. vim.fn.fnameescape(current_file))
    end

    -- Ensure the current buffer is attached to obsidian-ls after rename, no-op if attached
    require("obsidian.lsp").start(vim.api.nvim_get_current_buf())
  end)

  log.info("renamed " .. meta.count .. " reference(s) across " .. vim.tbl_count(meta.path_lookup) .. " file(s)")

  return note
end

return M
