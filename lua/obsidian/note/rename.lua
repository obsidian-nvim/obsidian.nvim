local M = {}

local Path = require "obsidian.path"
local api = require "obsidian.api"
local log = require "obsidian.log"
local refs = require "obsidian.parse.refs"
local search = require "obsidian.search"
local util = require "obsidian.util"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

---@param new_name string
---@return string
local function normalize_name(new_name)
  return vim.trim(tostring(new_name)):gsub("%.md$", "", 1)
end

local function strip_md_suffix(path)
  if vim.endswith(path, ".md") then
    return path:sub(1, #path - 3)
  end
  return path
end

local function add_replacement(replacements, seen, old_ref, new_ref)
  if not old_ref or not new_ref or old_ref == "" or seen[old_ref] then
    return
  end

  seen[old_ref] = true
  replacements[#replacements + 1] = { old = old_ref, new = new_ref }
end

local function add_replacement_variants(replacements, seen, old_ref, new_ref)
  add_replacement(replacements, seen, old_ref, new_ref)
  add_replacement(replacements, seen, util.urlencode(old_ref), util.urlencode(new_ref))
  add_replacement(
    replacements,
    seen,
    util.urlencode(old_ref, { keep_path_sep = true }),
    util.urlencode(new_ref, { keep_path_sep = true })
  )
end

local function relative_path(path, dir)
  if not dir then
    return path:vault_relative_path()
  end

  local ok, relpath = pcall(path.relative_to, path, Path.new(dir))
  return ok and tostring(relpath) or nil
end

local function path_replacements(old_path, new_path, include_stem_refs, dir)
  old_path = Path.new(old_path)
  new_path = Path.new(new_path)

  local replacements = {}
  local seen = {}

  if include_stem_refs then
    add_replacement_variants(replacements, seen, old_path.name, new_path.name)
    add_replacement_variants(replacements, seen, old_path.stem, new_path.stem)
  end

  local old_relpath = relative_path(old_path, dir)
  local new_relpath = relative_path(new_path, dir)
  if old_relpath and new_relpath then
    add_replacement_variants(replacements, seen, old_relpath, new_relpath)
    add_replacement_variants(replacements, seen, strip_md_suffix(old_relpath), strip_md_suffix(new_relpath))
  end

  return replacements
end

local function target_offset(ref)
  if ref.kind == "wiki" then
    local brackets = ref.raw:find("[[", 1, true)
    return brackets and brackets + 1 or nil
  elseif ref.kind == "markdown" then
    local close_bracket = ref.raw:find("](", 1, true)
    return close_bracket and close_bracket + 1 or nil
  end
end

local function find_target_replacement(ref, replacements)
  local body_offset = 0
  if ref.kind == "markdown" then
    if vim.startswith(ref.target, "./") then
      body_offset = 2
    elseif vim.startswith(ref.target, "/") then
      body_offset = 1
    end
  end

  local body = ref.target:sub(body_offset + 1)
  for _, replacement in ipairs(replacements) do
    if body == replacement.old then
      return body_offset, replacement
    end
  end
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
  local new_path = opts.new_path or (vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md")
  if tostring(new_path) ~= old_path and Path.new(new_path):exists() then
    return false, "Note with same name exists"
  end

  return true, nil
end

---@param path_pairs { old_path: string, new_path: string }[]
---@param opts? { include_file_rename: boolean|?, include_stem_refs: boolean|?, dir: string|obsidian.Path|? }
---@param callback fun(edit: lsp.WorkspaceEdit|nil, meta: obsidian.note.RenameMeta)
M.build_edit_for_paths = function(path_pairs, opts, callback)
  opts = opts or {}

  local include_file_rename = opts.include_file_rename ~= false
  local include_stem_refs = opts.include_stem_refs ~= false
  local dir = opts.dir or (path_pairs[1] and api.resolve_workspace_dir(path_pairs[1].old_path))
  local replacements = {}
  local seen = {}
  local search_refs = {}
  local search_seen = {}

  for _, pair in ipairs(path_pairs) do
    for _, replacement in ipairs(path_replacements(pair.old_path, pair.new_path, include_stem_refs, dir)) do
      if not seen[replacement.old] then
        seen[replacement.old] = true
        replacements[#replacements + 1] = replacement
      end
      if not search_seen[replacement.old] then
        search_seen[replacement.old] = true
        search_refs[#search_refs + 1] = replacement.old
      end
    end
  end

  table.sort(replacements, function(a, b)
    return #a.old > #b.old
  end)

  search.find_backlinks_async(nil, function(matches)
    local count = 0
    local path_lookup = {}
    local buf_list = {}
    local documentChanges = {}
    local file_edits = {}
    local file_order = {}
    local processed_lines = {}

    for _, match in ipairs(matches) do
      local match_path = tostring(match.path)
      local line_key = match_path .. ":" .. match.line

      if not processed_lines[line_key] then
        processed_lines[line_key] = true

        for _, ref in ipairs(refs.extract(match.text)) do
          local offset = target_offset(ref)
          local body_offset, replacement = find_target_replacement(ref, replacements)
          if offset and body_offset and replacement then
            local start_col = ref.range.start_col + offset + body_offset

            if not file_edits[match_path] then
              file_edits[match_path] = {}
              file_order[#file_order + 1] = match_path
            end

            file_edits[match_path][#file_edits[match_path] + 1] = {
              range = {
                start = { line = match.line - 1, character = start_col },
                ["end"] = { line = match.line - 1, character = start_col + #replacement.old },
              },
              newText = replacement.new,
            }
            count = count + 1
          end
        end
      end
    end

    for _, path in ipairs(file_order) do
      table.sort(file_edits[path], function(a, b)
        if a.range.start.line == b.range.start.line then
          return a.range.start.character > b.range.start.character
        end
        return a.range.start.line > b.range.start.line
      end)

      documentChanges[#documentChanges + 1] = {
        textDocument = {
          uri = vim.uri_from_fname(path),
          version = has_nvim_0_12 and vim.NIL or nil,
        },
        edits = file_edits[path],
      }

      buf_list[#buf_list + 1] = vim.fn.bufnr(path, true)
      path_lookup[path] = true
    end

    if include_file_rename then
      for _, pair in ipairs(path_pairs) do
        if pair.old_path ~= pair.new_path then
          documentChanges[#documentChanges + 1] = {
            kind = "rename",
            oldUri = vim.uri_from_fname(pair.old_path),
            newUri = vim.uri_from_fname(pair.new_path),
            options = {},
          }
        end
      end
    end

    local edit = #documentChanges > 0 and { documentChanges = documentChanges } or nil
    local first = path_pairs[1]

    callback(edit, {
      count = count,
      path_lookup = path_lookup,
      buf_list = buf_list,
      old_path = first and first.old_path or "",
      new_path = first and first.new_path or "",
    })
  end, { refs = search_refs, dir = dir })
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

  M.build_edit_for_paths({
    {
      old_path = old_path,
      new_path = new_path,
    },
  }, {
    include_file_rename = opts.include_file_rename,
    include_stem_refs = opts.include_stem_refs,
    dir = opts.dir,
  }, callback)
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
  require("obsidian.cache").notes.rename(old_path, new_path)
  if current_file == old_path then
    vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  elseif current_file ~= "" then
    vim.cmd("edit " .. vim.fn.fnameescape(current_file))
  end

  require("obsidian.lsp").start(note.bufnr or vim.api.nvim_get_current_buf())

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

  local old_path = opts.old_path or tostring(note.path)
  local new_path = opts.new_path or (vim.fs.joinpath(vim.fs.dirname(old_path), new_name) .. ".md")
  local old_stem = note.path and note.path.stem or nil
  if (new_name == note.id or (old_stem and new_name == old_stem)) and tostring(new_path) == old_path then
    log.info "Identical name"
    if callback then
      callback(nil, nil, nil)
    end
    return
  end

  local ok, err = M.validate(note, new_name, opts)
  if not ok then
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
