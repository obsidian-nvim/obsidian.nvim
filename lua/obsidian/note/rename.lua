local M = {}

local Path = require "obsidian.path"
local api = require "obsidian.api"
local log = require "obsidian.log"
local refs = require "obsidian.parse.refs"
local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local search = require "obsidian.search"
local uri = require "obsidian.uri"

local has_nvim_0_12 = (vim.fn.has "nvim-0.12.0" == 1)

---@param new_name string
---@return string
local function normalize_name(new_name)
  local name = vim.trim(tostring(new_name)):gsub("%.md$", "", 1)
  return name
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
  add_replacement(replacements, seen, uri.encode(old_ref), uri.encode(new_ref))
  add_replacement(
    replacements,
    seen,
    uri.encode(old_ref, { keep_path_sep = true }),
    uri.encode(new_ref, { keep_path_sep = true })
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
  if ref.kind == "markdown" or ref.kind == "wiki" then
    if ref.kind == "markdown" and vim.startswith(ref.target, "./") then
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
    local was_loaded = {}
    local originals = {}
    local documents = {}

    local function process_line(path, line, lnum)
      local line_key = path .. ":" .. lnum
      if processed_lines[line_key] then
        return
      end
      processed_lines[line_key] = true
      local document = documents[path]
      if not document then
        local bufnr = vim.fn.bufnr(path)
        local lines = bufnr > 0
            and vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          or vim.fn.readfile(path)
        document = Document.parse(lines)
        documents[path] = document
      end
      local row0 = lnum - 1
      ---@cast row0 integer
      for _, ref in ipairs(refs.extract(line, { row = row0, lexical = true })) do
        local origin = Range.new(row0, ref.range.start_col, row0, ref.range.start_col + 1)
        local offset = target_offset(ref)
        local body_offset, replacement = find_target_replacement(ref, replacements)
        if offset and body_offset and replacement and not document:intersects(origin, Document.INLINE_EXCLUSIONS) then
          local start_col = ref.range.start_col + offset + body_offset
          if not file_edits[path] then
            file_edits[path] = {}
            file_order[#file_order + 1] = path
          end
          file_edits[path][#file_edits[path] + 1] = {
            range = {
              start = { line = lnum - 1, character = start_col },
              ["end"] = { line = lnum - 1, character = start_col + #replacement.old },
            },
            newText = replacement.new,
          }
          originals[path] = originals[path] or {}
          originals[path][#originals[path] + 1] = { row = lnum - 1, col = start_col, text = replacement.old }
          count = count + 1
        end
      end
    end

    for _, match in ipairs(matches) do
      local path = tostring(match.path)
      local bufnr = vim.fn.bufnr(path)
      if bufnr < 1 or not vim.api.nvim_buf_is_loaded(bufnr) then
        process_line(path, match.text, match.line)
      end
    end
    -- A loaded buffer is authoritative even if its unsaved links are absent
    -- from the ripgrep results on disk.
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local path = vim.api.nvim_buf_get_name(bufnr)
        if path ~= "" and api.path_is_note(path, api.find_workspace(assert(dir, "rename workspace is required"))) then
          for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
            process_line(path, line, row)
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

      local existing_buf = vim.fn.bufnr(path)
      was_loaded[path] = existing_buf > 0 and vim.api.nvim_buf_is_loaded(existing_buf)
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
      was_loaded = was_loaded,
      originals = originals,
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
  }, function(edit, meta)
    if opts.repair_collisions ~= true then
      return callback(edit, meta)
    end

    local plan = require("obsidian.link.collision").plan { old_path = old_path, new_path = new_path }
    meta.collision_plan = plan
    if not plan or plan.count == 0 then
      return callback(edit, meta)
    end
    edit = edit or { documentChanges = {} }
    local changes = assert(edit.documentChanges, "rename edit must use documentChanges")
    for path, edits in pairs(plan.edits) do
      local change
      for _, entry in ipairs(changes) do
        if entry.textDocument and vim.uri_to_fname(entry.textDocument.uri) == path then
          change = entry
          break
        end
      end
      if not change then
        change = {
          textDocument = {
            uri = vim.uri_from_fname(path),
            version = has_nvim_0_12 and vim.NIL or nil,
          },
          edits = {},
        }
        table.insert(changes, 1, change)
      end
      for _, target_edit in ipairs(edits) do
        local overlaps = false
        for _, existing in ipairs(change.edits) do
          if vim.deep_equal(existing.range, target_edit.range) then
            overlaps = true
            break
          end
        end
        if not overlaps then
          change.edits[#change.edits + 1] = target_edit
          local original
          -- Match originals by range; the ordinary rename edits may already
          -- occupy this document's edit list.
          for i, candidate in ipairs(edits) do
            if candidate == target_edit then
              original = plan.original[path][i]
              break
            end
          end
          meta.originals[path] = meta.originals[path] or {}
          meta.originals[path][#meta.originals[path] + 1] = original
          meta.count = meta.count + 1
        end
      end
      meta.path_lookup[path] = true
      local existing_buf = vim.fn.bufnr(path)
      meta.was_loaded[path] = existing_buf > 0 and vim.api.nvim_buf_is_loaded(existing_buf)
      meta.buf_list[#meta.buf_list + 1] = vim.fn.bufnr(path, true)
    end
    callback(edit, meta)
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
  note:update_frontmatter(note.bufnr)

  -- Write only files opened for this edit; leave pre-existing dirty buffers
  -- (including unrelated notes) under the user's control.
  for path, loaded in pairs(meta.was_loaded) do
    if not loaded then
      local bufnr = vim.fn.bufnr(path)
      if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd "silent noautocmd write"
        end)
        vim.api.nvim_buf_delete(bufnr, { unload = true })
      end
    end
  end
  if note.bufnr and vim.api.nvim_buf_is_valid(note.bufnr) then
    vim.api.nvim_buf_call(note.bufnr, function()
      vim.cmd "silent write"
    end)
  end
  require("obsidian.cache").notes.rename(old_path, new_path)
  if current_file == old_path then
    vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  end

  require("obsidian.lsp").start(note.bufnr or vim.api.nvim_get_current_buf())

  log.info("Updated %d links in %d notes", meta.count, vim.tbl_count(meta.path_lookup))
end

---@param edit lsp.WorkspaceEdit
---@param old_path string
---@param new_path string
---@return table<string, table<integer, string>>
local function expected_rename_lines(edit, old_path, new_path)
  local apply = require "obsidian.link.collision_apply"
  local expected = {}
  for _, change in ipairs(edit.documentChanges or {}) do
    if change.textDocument then
      local source = vim.uri_to_fname(change.textDocument.uri)
      local edits = vim.deepcopy(change.edits)
      table.sort(edits, function(a, b)
        local x, y = a.range.start, b.range.start
        return x.line > y.line or (x.line == y.line and x.character > y.character)
      end)
      expected[source == old_path and new_path or source] = apply.expected_lines(source, edits)
    end
  end
  return expected
end

local function rename_edit_applied(expected, old_path, new_path)
  if not Path.new(new_path):is_file() or Path.new(old_path):is_file() then
    return false
  end
  local apply = require "obsidian.link.collision_apply"
  for path, lines in pairs(expected) do
    if not apply.edits_applied(path, lines) then
      return false
    end
  end
  return true
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
    ---@cast err string
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

  local build_opts = vim.tbl_extend("force", { repair_collisions = true }, opts)
  local release = function() end
  local function build(attempt)
    M.build_edit(note, new_name, build_opts, function(edit, meta)
      if not meta then
        if callback then
          callback(nil, edit, nil)
        end
        release()
        return
      end
      local plan = meta.collision_plan
      if
        plan
        and plan.count > 0
        and not require("obsidian.link.collision_apply").confirm(plan, {
          count = meta.count,
          notes = vim.tbl_count(meta.path_lookup),
          edit = edit,
          rename = true,
        })
      then
        if callback then
          callback("Aborted", nil, nil)
        end
        release()
        return
      end
      if plan then
        local fresh = require("obsidian.link.collision").plan { old_path = old_path, new_path = new_path }
        if not fresh or not vim.deep_equal(plan.edits, fresh.edits) then
          if attempt == 0 then
            return build(1)
          end
          release()
          return fail("Link collision changed during rename; retry", callback)
        end
      end
      if not edit then
        if callback then
          callback(nil, nil, meta)
        end
        release()
        return
      end
      local current_lines = require("obsidian.link.collision_apply").current_lines
      for path, originals in pairs(meta.originals) do
        local lines = current_lines(path)
        for _, original in ipairs(originals) do
          local line = lines[original.row + 1]
          if not line or line:sub(original.col + 1, original.col + #original.text) ~= original.text then
            if attempt == 0 then
              return build(1)
            end
            release()
            return fail("Link target changed during rename; retry", callback)
          end
        end
      end
      for _, change in ipairs(edit.documentChanges or {}) do
        if change.textDocument then
          local path = vim.uri_to_fname(change.textDocument.uri)
          local bufnr = vim.fn.bufnr(path)
          if
            (
              bufnr > 0
              and vim.api.nvim_buf_is_loaded(bufnr)
              and (vim.bo[bufnr].readonly or not vim.bo[bufnr].modifiable)
            ) or ((bufnr < 1 or not vim.api.nvim_buf_is_loaded(bufnr)) and vim.fn.filewritable(path) ~= 1)
          then
            release()
            return fail("Reference note is not writable: " .. path, callback)
          end
        end
      end

      local expected = expected_rename_lines(edit, old_path, new_path)
      if opts.apply ~= false then
        local applied, apply_err = pcall(vim.lsp.util.apply_workspace_edit, edit, opts.offset_encoding or "utf-8")
        if not applied or not rename_edit_applied(expected, old_path, new_path) then
          release()
          return fail("Rename edit failed: " .. tostring(apply_err), callback)
        end
        if callback then
          callback(nil, edit, meta)
        end
        if opts.update_buffers ~= false then
          vim.schedule(function()
            local ok_finish, finish_err = pcall(finish_rename, note, new_name, meta)
            if not ok_finish then
              log.err("Rename applied, but post-rename update failed: %s", finish_err)
            end
            release()
          end)
        else
          release()
        end
      else
        -- The LSP rename response has no apply acknowledgment. Only finish if
        -- a later filesystem check proves that the client applied the rename.
        if callback then
          callback(nil, edit, meta)
        end
        if opts.update_buffers ~= false then
          local tries = 0
          local function verify()
            tries = tries + 1
            if rename_edit_applied(expected, old_path, new_path) then
              local ok_finish, finish_err = pcall(finish_rename, note, new_name, meta)
              if not ok_finish then
                log.err("Rename applied, but post-rename update failed: %s", finish_err)
              end
              release()
            elseif tries < 100 then
              vim.defer_fn(verify, 10)
            else
              log.warn "Rename edit was not confirmed; no links reported as updated"
              release()
            end
          end
          vim.schedule(verify)
        else
          release()
        end
      end
    end)
  end
  require("obsidian.link.queue").run(new_path, function(done)
    release = done
    local valid, reason = M.validate(note, new_name, opts)
    if not valid then
      release()
      return fail(assert(reason, "rename validation failed"), callback)
    end
    build(0)
  end, { immediate = true })
end

return M
