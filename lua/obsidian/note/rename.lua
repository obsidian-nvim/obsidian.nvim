local M = {}

local Path = require "obsidian.path"
local api = require "obsidian.api"
local log = require "obsidian.log"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

---@param new_name string
---@return string
local function normalize_name(new_name)
  return vim.trim(tostring(new_name)):gsub("%.md$", "", 1)
end

---@param note obsidian.Note
---@param old_path string
---@return obsidian.Note
local function build_search_note(note, old_path)
  local search_note = vim.tbl_extend("force", {}, note, { path = Path.new(old_path) })
  return setmetatable(search_note, getmetatable(note))
end

---@param err string
---@param callback? fun(err: string|nil, edit: lsp.WorkspaceEdit|nil, meta: obsidian.note.RenameMeta|nil)
---@return nil
local function fail(err, callback)
  log.err(err)
  if callback then
    callback(err, nil, nil)
    return nil
  end
  error(err, 3)
end

---@param note obsidian.Note
---@param new_name string
---@param opts? obsidian.note.RenameOpts
---@return boolean
---@return string?
M.validate = function(note, new_name, opts)
  opts = opts or {}
  new_name = normalize_name(new_name)

  local Note = require "obsidian.note"
  local valid, reason = Note.is_valid_filename(new_name)
  if not valid then
    return false, ("Invalid filename %q: %s"):format(new_name, reason)
  end

  if opts.check_unique == false then
    return true, nil
  end

  local old_path = opts.old_path or tostring(note.path)
  for path in api.dir(Obsidian.dir) do
    path = Path.new(path)
    if tostring(path) ~= old_path then
      if new_name == path.stem then
        return false, "Note with same name exists"
      end
      local other = Note.from_file(path)
      if other and new_name == other.id then
        return false, "Note with same name exists"
      end
    end
  end

  return true, nil
end

---@param note obsidian.Note
---@param new_name string
---@param opts? obsidian.note.RenameOpts
---@param callback fun(edit: lsp.WorkspaceEdit|nil, meta: obsidian.note.RenameMeta)
M.build_edit = function(note, new_name, opts, callback)
  opts = opts or {}
  new_name = normalize_name(new_name)

  local old_path = opts.old_path or tostring(assert(note.path, "note path is required"))
  local new_path = opts.new_path or (vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md")
  local include_file_rename = opts.include_file_rename ~= false
  local search_note = build_search_note(note, old_path)
  local old_refs = search_note:get_reference_paths()
  -- Pre-compute url-encoded refs for backlink search so backlinks() doesn't repeat get_reference_paths().
  local search_refs = search_note:get_reference_paths { urlencode = true }

  -- Sort refs by length (longest first) to match most specific reference first.
  table.sort(old_refs, function(a, b)
    return #a > #b
  end)

  search_note:backlinks_async({ refs = search_refs }, function(matches)
    local count = 0
    local path_lookup = {}
    local buf_list = {}
    local documentChanges = {}

    -- Track which lines we've already processed to avoid duplicates.
    local processed_lines = {}

    for _, match in ipairs(matches) do
      local match_path = tostring(match.path)
      local line_key = match_path .. ":" .. match.line

      if not processed_lines[line_key] then
        processed_lines[line_key] = true

        -- Find all occurrences of refs in this line.
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

            -- Longer refs win when matches overlap.
            local dominated = false
            for _, existing in ipairs(line_edits) do
              if offset_st >= existing.start_1idx and offset_ed <= existing.end_1idx then
                dominated = true
                break
              end
            end

            if not dominated then
              line_edits[#line_edits + 1] = {
                start_1idx = offset_st,
                end_1idx = offset_ed,
                -- LSP with utf-8 offset_encoding expects byte positions (0-indexed).
                replace_st = offset_st - 1,
                replace_ed = offset_ed,
                new_text = new_text,
              }
            end

            search_start = offset_ed + 1
          end
        end

        -- Sort edits right-to-left so edits don't affect each other's positions.
        table.sort(line_edits, function(a, b)
          return a.start_1idx > b.start_1idx
        end)

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

    callback(edit, {
      count = count,
      path_lookup = path_lookup,
      buf_list = buf_list,
      old_path = old_path,
      new_path = new_path,
    })
  end)
end

---@param note obsidian.Note
---@param new_name string
---@param meta obsidian.note.RenameMeta
local function finish_rename(note, new_name, meta)
  local current_file = vim.api.nvim_buf_get_name(0)
  local new_path = meta.new_path
  local old_path = meta.old_path

  if not note.bufnr then
    note.bufnr = vim.fn.bufnr(new_path, true)
  end

  -- Ensure files with renamed refs display correctly.
  for _, bufnr in ipairs(meta.buf_list) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.bo[bufnr].filetype = "markdown"
    end
  end

  note.id = new_name
  note.path = Path.new(new_path)
  note:save_to_buffer { bufnr = note.bufnr }

  vim.cmd "silent! wall"
  if current_file == old_path then
    vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  elseif current_file ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(current_file))
  end

  require("obsidian.lsp").start(vim.api.nvim_get_current_buf())

  log.info("renamed " .. meta.count .. " reference(s) across " .. vim.tbl_count(meta.path_lookup) .. " file(s)")
end

---@param note obsidian.Note
---@param new_name string
---@param opts? obsidian.note.RenameOpts
---@param callback? fun(err: string|nil, edit: lsp.WorkspaceEdit|nil, meta: obsidian.note.RenameMeta|nil)
M.rename = function(note, new_name, opts, callback)
  if type(opts) == "function" then
    callback = opts
    opts = {}
  end
  opts = opts or {}
  new_name = normalize_name(new_name)

  if opts.apply == false and callback == nil then
    return fail("callback is required when rename opts.apply is false", nil)
  end

  local old_stem = note.path and note.path.stem or nil
  if new_name == note.id or (old_stem and new_name == old_stem) then
    log.info "Identical name"
    if callback then
      callback(nil, nil, nil)
    end
    return
  end

  local ok, err = M.validate(note, new_name, opts)
  if not ok then
    err = assert(err)
    if err == "Note with same name exists" then
      log.info(err)
      if callback then
        callback(err, nil, nil)
        return
      end
      error(err, 2)
    end
    return fail(err, callback)
  end

  M.build_edit(note, new_name, opts, function(edit, meta)
    if opts.apply ~= false and edit then
      vim.lsp.util.apply_workspace_edit(edit, opts.offset_encoding or "utf-8")
    end

    if callback then
      callback(nil, edit, meta)
    end

    if opts.update_buffers ~= false then
      -- Run after the edit has been applied. With opts.apply=false the caller is
      -- expected to apply the returned edit synchronously from the callback.
      vim.schedule(function()
        finish_rename(note, new_name, meta)
      end)
    end
  end)
end

return M
