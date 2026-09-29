local fs_util = require "obsidian.util.fs"
local attachment = require "obsidian.attachment"
local link = require "obsidian.link"
local api = require "obsidian.api"
local picker_util = require "obsidian.picker.util"
local note_matcher = require "obsidian.search.note_matcher"
local log = require "obsidian.log"

local M = {}

---@class obsidian.cache.FindNotesOpts
---@field dir string|obsidian.Path|?
---@field search obsidian.SearchOpts|?
---@field notes obsidian.note.LoadOpts|?
---@field match obsidian.search.NoteMatchOpts|?

---@class obsidian.cache.FindAttachmentsOpts
---@field dir string|obsidian.Path|?
---@field search obsidian.SearchOpts|?

---@class obsidian.Ref
---@field kind "note"|"attachment"|"unresolved"|"tag"
---@field text string
---@field path string|?
---@field note obsidian.Note|?
---@field attachment boolean|?
---@field target string|?
---@field references obsidian.NoteCreationReference[]|?

---@class obsidian.cache.FindRefsOpts
---@field dir string|obsidian.Path|?
---@field include_notes boolean|?
---@field include_attachments boolean|?
---@field include_unresolved boolean|?
---@field include_tags boolean|? Reserved until tags are cache-powered.

---@param path string
---@param dir string
---@return boolean
local function path_is_template(path, dir)
  local workspace = api.find_workspace(dir)
  local templates_dir = workspace and api.templates_dir(workspace) or nil
  return templates_dir ~= nil and fs_util.is_subpath(path, tostring(templates_dir))
end

---@param paths string[]
---@param rows table<string, table>
---@param search_opts obsidian.SearchOpts|?
local function sort_cached_paths(paths, rows, search_opts)
  search_opts = search_opts or {}
  if search_opts.sort == false then
    return
  end
  local global_search = (Obsidian.opts and Obsidian.opts.search) or {}
  local sort_by = global_search.sort_by
  if sort_by == false then
    return
  end
  sort_by = sort_by or "path"
  local reversed = global_search.sort_reversed or false
  table.sort(paths, function(a, b)
    ---@type string|number
    local av = a
    ---@type string|number
    local bv = b
    if sort_by == "modified" then
      local a_stat, b_stat = rows[a].stat or {}, rows[b].stat or {}
      av = (a_stat.mtime_sec or 0) * 1000000000 + (a_stat.mtime_nsec or 0)
      bv = (b_stat.mtime_sec or 0) * 1000000000 + (b_stat.mtime_nsec or 0)
    elseif sort_by == "accessed" or sort_by == "created" then
      local stat_key = sort_by == "accessed" and "atime" or "birthtime"
      local a_stat, b_stat = vim.uv.fs_stat(a), vim.uv.fs_stat(b)
      av = a_stat and a_stat[stat_key] and a_stat[stat_key].sec or 0
      bv = b_stat and b_stat[stat_key] and b_stat[stat_key].sec or 0
    end
    if av == bv then
      return a < b
    elseif reversed then
      return av > bv
    else
      return av < bv
    end
  end)
end

---Find existing cached notes using the same structured domains as search.find_notes().
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.cache.FindNotesOpts|?
---@return obsidian.Note[]
M.find_notes = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local search_opts = opts.search or {}
  local root = vim.fs.normalize(tostring(Obsidian.dir))
  local rows = cache.notes.all()
  local paths = {}

  for path, row in pairs(rows) do
    if
      fs_util.is_subpath(path, dir)
      and not path_is_template(path, dir)
      and note_matcher.matches(path, root, row, term, opts.match, search_opts.ignore_case)
    then
      paths[#paths + 1] = path
    end
  end
  sort_cached_paths(paths, rows, search_opts)

  local Note = require "obsidian.note"
  local load_opts = opts.notes or {}
  local parse_file = load_opts.collect_sections
    or load_opts.collect_anchor_links
    or load_opts.collect_blocks
    or load_opts.collect_block_candidates
  local notes = {}
  local first_err, first_err_path
  local err_count = 0
  for _, path in ipairs(paths) do
    local ok, note
    if parse_file then
      ok, note = pcall(Note.from_file, path, load_opts)
    else
      ok, note = pcall(Note.from_cache, path, rows[path])
    end
    if ok then
      notes[#notes + 1] = note
    else
      err_count = err_count + 1
      if not first_err then
        first_err, first_err_path = note, path
      end
    end
  end
  if first_err then
    log.err(
      "%d error(s) occurred during cached note search. First error from '%s':\n%s",
      err_count,
      first_err_path,
      first_err
    )
  end
  return notes
end

---Find existing cached attachments.
---The cache must be ready before calling this function.
---@param term string
---@param opts obsidian.cache.FindAttachmentsOpts|?
---@return string[]
M.find_attachments = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local root = vim.fs.normalize(tostring(Obsidian.dir))
  local query = vim.trim(term or "")
  local ignore_case = opts.search == nil or opts.search.ignore_case ~= false
  if ignore_case then
    query = query:lower()
  end
  local rows = cache.attachments.all()
  local paths = {}
  for path in pairs(rows) do
    local rel = fs_util.relpath(root, path) or path
    local haystack = rel
    if ignore_case then
      haystack = haystack:lower()
    end
    if fs_util.is_subpath(path, dir) and (query == "" or haystack:find(query, 1, true)) then
      paths[#paths + 1] = path
    end
  end
  sort_cached_paths(paths, rows, opts.search)
  return paths
end

---@param entry obsidian.PickerEntry
---@return obsidian.ui_select_preview_spec
local function preview_picker_entry(entry)
  local cache = require "obsidian.cache"
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local data = entry.user_data or {}
  if data.missing then
    local references = vim.deepcopy(data.references or {})
    table.sort(references, function(a, b)
      local a_path = cache.notes.rel_path(a.filename)
      local b_path = cache.notes.rel_path(b.filename)
      if a_path ~= b_path then
        return a_path < b_path
      elseif a.lnum ~= b.lnum then
        return a.lnum < b.lnum
      else
        return a.col < b.col
      end
    end)
    local lines = {}
    for i, reference in ipairs(references) do
      if i > 1 then
        lines[#lines + 1] = ""
      end
      lines[#lines + 1] = ("%s:%d:%d"):format(cache.notes.rel_path(reference.filename), reference.lnum, reference.col)
      lines[#lines + 1] = ""
      lines[#lines + 1] = "```markdown"
      lines[#lines + 1] = reference.raw
      lines[#lines + 1] = "```"
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
  elseif entry.filename then
    return picker_util.preview_path(entry.filename)
  end

  return { buf = buf }
end

---@param target string?
---@return boolean
local function is_external_target(target)
  return target == nil or target == "" or target:match "^%a[%w+.-]*:" ~= nil
end

---@param target string
---@return string
local function normalize_link_target(target)
  target = vim.uri_decode(target):gsub("\\", "/")
  while vim.startswith(target, "./") do
    target = target:sub(3)
  end
  return (target:gsub("^/+", ""))
end

---@param path string
---@param lookup table<string, boolean>
local function add_lookup_path(path, lookup)
  local cache = require "obsidian.cache"
  local path_no_ext = path:gsub("%.md$", "")
  local rel_path = cache.notes.rel_path(path)
  local rel_path_no_ext = rel_path:gsub("%.md$", "")
  local basename = vim.fn.fnamemodify(path, ":t")
  for _, key in ipairs {
    path,
    path_no_ext,
    rel_path,
    rel_path_no_ext,
    basename,
    vim.fn.fnamemodify(path, ":t:r"),
  } do
    lookup[key:lower()] = true
  end
end

---@param target string
---@param lookup table<string, boolean>
---@param source_path string
---@return boolean
local function target_exists(target, lookup, source_path)
  local decoded = vim.uri_decode(target):gsub("\\", "/")
  local candidates
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    local absolute = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded))
    local absolute_no_ext = absolute:gsub("%.md$", "")
    candidates = { absolute, absolute_no_ext, absolute .. ".md" }
  else
    local normalized = normalize_link_target(target)
    local normalized_no_ext = normalized:gsub("%.md$", "")
    candidates = { normalized, normalized_no_ext, normalized .. ".md" }
  end

  for _, key in ipairs(candidates) do
    if lookup[key:lower()] then
      return true
    end
  end
  return false
end

---@param target string
---@param source_path string
---@param target_path string
---@param is_attachment boolean
---@return string
local function missing_entry_key(target, source_path, target_path, is_attachment)
  if is_attachment then
    return target_path:lower()
  end

  local decoded = vim.uri_decode(target):gsub("\\", "/")
  if vim.startswith(decoded, "./") or vim.startswith(decoded, "../") then
    return vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source_path), decoded)):lower()
  end
  return normalize_link_target(decoded):lower()
end

---@param is_attachment boolean
---@param missing boolean
---@param references obsidian.NoteCreationReference[]?
---@param target string?
---@return obsidian.PickerEntryUserData
local function entry_user_data(is_attachment, missing, references, target)
  return {
    attachment = is_attachment,
    missing = missing,
    references = references,
    target = target,
  }
end

---Find note, attachment, and unresolved-link references from one cache snapshot.
---The cache must be ready before calling this function. Tags are reserved for a
---future cache-powered reference kind.
---@param term string
---@param opts obsidian.cache.FindRefsOpts|?
---@return obsidian.Ref[]
M.find_refs = function(term, opts)
  local cache = require "obsidian.cache"
  assert(cache.is_ready(), "cache not ready")
  opts = opts or {}
  local include_notes = opts.include_notes ~= false
  local include_attachments = opts.include_attachments == true
  local include_unresolved = opts.include_unresolved == true
  -- TODO: honor opts.include_tags once tags are exposed as cache-powered references.
  local dir = vim.fs.normalize(tostring(opts.dir or Obsidian.dir))
  local query = vim.trim(term or ""):lower()
  local notes = cache.notes.all()
  local attachments = cache.attachments.all()
  local lookup = {}
  ---@type obsidian.Ref[]
  local refs = {}
  ---@type table<string, obsidian.Ref>
  local unresolved = {}

  ---@param ref obsidian.Ref
  ---@return obsidian.Ref?
  local function add_ref(ref)
    if query ~= "" and not ref.text:lower():find(query, 1, true) then
      return
    end
    refs[#refs + 1] = ref
    return ref
  end

  for path, row in pairs(notes) do
    add_lookup_path(path, lookup)
    for _, alias in ipairs(row.aliases or {}) do
      lookup[alias:lower()] = true
    end
  end
  for path in pairs(attachments) do
    add_lookup_path(path, lookup)
  end

  local Note = require "obsidian.note"
  if include_notes then
    for path, row in pairs(notes) do
      if fs_util.is_subpath(path, dir) and not path_is_template(path, dir) then
        local text = note_matcher.without_note_extension(cache.notes.rel_path(path))
        local note = Note.from_cache(path, row)
        add_ref { kind = "note", text = text, path = path, note = note, attachment = false }
        for _, alias in ipairs(row.aliases or {}) do
          add_ref {
            kind = "note",
            text = text .. " | " .. alias,
            path = path,
            note = note,
            attachment = false,
          }
        end
      end
    end
  end

  if include_attachments then
    for path in pairs(attachments) do
      if fs_util.is_subpath(path, dir) then
        add_ref {
          kind = "attachment",
          text = cache.attachments.rel_path(path),
          path = path,
          attachment = true,
        }
      end
    end
  end

  if include_unresolved then
    for source_path, row in pairs(notes) do
      if not path_is_template(source_path, dir) then
        for _, outgoing in ipairs(row.links_out or {}) do
          local target = outgoing.target
          if not is_external_target(target) and not target_exists(target, lookup, source_path) then
            local target_is_attachment = attachment.is_attachment_path(target:lower())
            if include_attachments or not target_is_attachment then
              local target_path = link.missing_link_path(target, source_path)
              if target_path and fs_util.is_subpath(target_path, dir) then
                local key = missing_entry_key(target, source_path, target_path, target_is_attachment)
                ---@type obsidian.NoteCreationReference
                local reference = {
                  filename = source_path,
                  lnum = outgoing.line or 1,
                  col = outgoing.col or 1,
                  raw = outgoing.raw or target,
                }
                local existing = unresolved[key]
                if existing then
                  local references = assert(existing.references, "unresolved reference locations are missing")
                  references[#references + 1] = reference
                else
                  local ref = {
                    kind = "unresolved",
                    text = normalize_link_target(target),
                    path = target_path,
                    target = vim.uri_decode(target):gsub("\\", "/"),
                    attachment = target_is_attachment,
                    references = { reference },
                  }
                  if add_ref(ref) then
                    unresolved[key] = ref
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  table.sort(refs, function(a, b)
    if a.text ~= b.text then
      return a.text < b.text
    end
    return (a.path or "") < (b.path or "")
  end)
  return refs
end

---@param opts obsidian.PickerFindOpts|?
---@return boolean handled
M.find_files = function(opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  if not cache.is_enabled() or opts.include_non_markdown then
    return false
  end

  local show_existing_only = opts.show_existing_only ~= false
  local show_attachments = opts.show_attachments == true
  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or vim.fs.normalize(tostring(Obsidian.dir))
  if not fs_util.is_subpath(dir, tostring(Obsidian.dir)) then
    return false
  end

  cache.when_ready(function()
    local query = opts.query and vim.trim(opts.query) or nil
    if query == "" then
      query = nil
    end

    ---@type obsidian.PickerEntry[]
    local entries = {}
    for _, ref in
      ipairs(M.find_refs(query or "", {
        dir = dir,
        include_notes = true,
        include_attachments = show_attachments,
        include_unresolved = not show_existing_only,
        include_tags = false,
      }))
    do
      entries[#entries + 1] = {
        text = ref.text,
        filename = ref.path,
        user_data = entry_user_data(ref.attachment == true, ref.kind == "unresolved", ref.references, ref.target),
      }
    end

    local pick_query = opts.query
    if query and #entries > 0 then
      pick_query = nil
    end

    local picker = require "obsidian.picker"

    picker.select(entries, {
      prompt = opts.prompt_title,
      allow_multiple = true,
      -- The cache has already applied the initial query case-insensitively.
      -- Don't pass it through, since some pickers would filter again case-sensitively.
      query = pick_query,
      query_mappings = opts.query_mappings,
      selection_mappings = opts.selection_mappings,
      preview_item = preview_picker_entry,
    }, function(items)
      local paths = vim.tbl_filter(
        function(path)
          return path ~= nil
        end,
        vim.tbl_map(function(item)
          return item["filename"]
        end, items)
      )
      if opts.callback then
        opts.callback(paths)
        return
      end

      local selected_notes = {}
      for _, item in ipairs(items) do
        local path = item.filename
        local data = item.user_data or {}
        local is_missing_attachment = data.attachment and data.missing
        if path and is_missing_attachment then
          require("obsidian.actions").add_attachment(nil, {
            insert = false,
            bufnr = require("obsidian.picker").state.calling_bufnr,
            dst = path,
          })
        elseif path and data.attachment then
          vim.ui.open(path)
        elseif path and data.missing then
          local choice = api.confirm("How to handle missing reference?", "&Create New Note\n&Open References")
          if choice == "Create New Note" then
            local location = data.target or cache.notes.rel_path(path):gsub("%.md$", "")
            api.create_new_note(location, function(locations)
              if locations and locations[1] then
                api.open_note(vim.uri_to_fname(locations[1].uri))
              end
            end, {
              references = data.references,
              source_path = data.references and data.references[1] and data.references[1].filename or nil,
            })
          elseif choice == "Open References" then
            picker.select(data.references, { prompt = "Unresolved References" }, function(choices)
              picker_util.open_notes(choices)
            end)
          end
        elseif path then
          selected_notes[#selected_notes + 1] = item
        end
      end
      picker_util.open_notes(selected_notes)
    end)
  end)

  return true
end

return M
