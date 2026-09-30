local Document = require "obsidian.parse.document"
local Path = require "obsidian.path"
local Range = require "obsidian.range"
local compat = require "obsidian.compat"
local header = require "obsidian.parse.header"
local block_id = require "obsidian.parse.block_id"
local log = require "obsidian.log"
local async = require "obsidian.async"
local api = require "obsidian.api"
local tags = require "obsidian.tag"
local fs_util = require "obsidian.util.fs"
local note_matcher = require "obsidian.search.note_matcher"

local M = {}

local Filesystem = require "obsidian.search.filesystem"
local Handle = require "obsidian.search.handle"
local Ripgrep = require "obsidian.search.ripgrep"

local TAG_CHARS_REQUIRED_RG = [[[\p{L}\p{N}_/-]+[\p{L}\p{N}_/-]*[\p{L}_/-]+[\p{L}\p{N}_/-]*]]

--- Search markdown files in a directory for a given term. Each match is passed to the `on_match` callback.
---
---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.BackendOpts|?
---@param on_match fun(match: obsidian.search.MatchData)
---@param on_exit fun(exit_code: integer)|?
---@return obsidian.search.AsyncHandle
M.search_async = function(dir, term, opts, on_match, on_exit)
  return Ripgrep.search_async(dir, term, opts, on_match, on_exit)
end

--- Find files in a directory matching a given term. Each matching path is
--- passed to the `on_match` callback. Ripgrep is preferred, with the native
--- filesystem backend used when it is unavailable or fails.
---
---@param dir string|obsidian.Path
---@param term string?
---@param opts obsidian.search.BackendOpts|?
---@param on_match fun(path: string)
---@param on_exit fun(exit_code: integer)|?
---@return obsidian.search.AsyncHandle
M.find_async = function(dir, term, opts, on_match, on_exit)
  return Ripgrep.find_async(dir, term, opts, on_match, on_exit)
end

---@param dir string|obsidian.Path|nil
---@return boolean
local function cache_can_search(dir)
  local cache = require "obsidian.cache"
  if not cache.is_enabled() or not Obsidian or not Obsidian.dir then
    return false
  end
  local search_dir = Path.new(dir or api.resolve_workspace_dir()):resolve { strict = true }
  local vault_dir = Path.new(Obsidian.dir):resolve { strict = true }
  return fs_util.is_subpath(tostring(search_dir), tostring(vault_dir))
end

local filesystem_methods = {
  find_notes = Filesystem.find_notes_async,
  find_attachments = Filesystem.find_attachments_async,
  find_refs = Filesystem.find_refs_async,
}

---@param method "find_notes"|"find_attachments"|"find_refs"
---@param term string
---@param opts table
---@param callback fun(results: any[], err: string?)
---@return obsidian.search.AsyncHandle
local function dispatch_async(method, term, opts, callback)
  local cancelled = false
  local child
  local scheduled_callback = vim.schedule_wrap(function(...)
    if not cancelled then
      callback(...)
    end
  end)
  local handle = Handle.new(function()
    cancelled = true
    Handle.cancel(child)
  end)

  if not cache_can_search(opts.dir) then
    child = filesystem_methods[method](term, scheduled_callback, opts)
    return handle
  end

  local cache = require "obsidian.cache"
  cache.when_ready(function()
    if cancelled then
      return
    end
    local ok, result = pcall(cache[method], term, opts)
    if ok then
      scheduled_callback(result)
    else
      scheduled_callback({}, tostring(result))
    end
  end)
  return handle
end

---Find notes using the cache backend when possible, otherwise the filesystem backend.
---@param term string
---@param callback fun(notes: obsidian.Note[], err: string?)
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.search.AsyncHandle
M.find_notes_async = function(term, callback, opts)
  opts = opts or {}
  opts.dir = opts.dir or api.resolve_workspace_dir()
  return dispatch_async("find_notes", term, opts, callback)
end

---Find notes matching a structured search term.
---@param term string
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.Note[] notes
---@return string? err
M.find_notes = function(term, opts)
  opts = opts or {}
  local result, err = async.block_on(function(cb)
    return M.find_notes_async(term, cb, opts)
  end, opts.timeout or 3000)
  if result == nil then
    return {}, err or "note search timed out"
  end
  return result, err
end

---Find attachment paths matching a filename or vault-relative path.
---@param term string
---@param callback fun(paths: string[], err: string?)
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return obsidian.search.AsyncHandle
M.find_attachments_async = function(term, callback, opts)
  opts = opts or {}
  opts.dir = opts.dir or api.resolve_workspace_dir()
  return dispatch_async("find_attachments", term, opts, callback)
end

---@param term string
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return string[] paths
---@return string? err
M.find_attachments = function(term, opts)
  opts = opts or {}
  local result, err = async.block_on(function(cb)
    return M.find_attachments_async(term, cb, opts)
  end, opts.timeout or 3000)
  if result == nil then
    return {}, err or "attachment search timed out"
  end
  return result, err
end

---Find typed note, attachment, and unresolved-link targets.
---@param term string
---@param callback fun(refs: obsidian.Ref[], err: string?)
---@param opts obsidian.search.FindRefsOpts|?
---@return obsidian.search.AsyncHandle
M.find_refs_async = function(term, callback, opts)
  opts = opts or {}
  opts.dir = opts.dir or api.resolve_workspace_dir()
  return dispatch_async("find_refs", term, opts, callback)
end

---@param term string
---@param opts obsidian.search.FindRefsOpts|?
---@return obsidian.Ref[] refs
---@return string? err
M.find_refs = function(term, opts)
  opts = opts or {}
  local result, err = async.block_on(function(cb)
    return M.find_refs_async(term, cb, opts)
  end, opts.timeout or 5000)
  if result == nil then
    return {}, err or "reference search timed out"
  end
  return result, err
end

---@param query string
---@param callback fun(notes: obsidian.Note[], err: string?)
---@param opts { collect: obsidian.search.NoteCollectOpts|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
---@return obsidian.search.AsyncHandle
M.resolve_note_async = function(query, callback, opts)
  local cancelled = false
  local scheduled_callback = vim.schedule_wrap(function(...)
    if not cancelled then
      callback(...)
    end
  end)
  local child
  local handle = Handle.new(function()
    cancelled = true
    Handle.cancel(child)
  end)
  local function finish(notes, err)
    scheduled_callback(notes, err)
  end
  opts = opts or {}
  local parse_opts = note_matcher.parse_opts { collect = opts.collect }
  local Note = require "obsidian.note"
  local workspace_dir = Path.new(opts.dir or api.resolve_workspace_dir())

  -- Autocompletion for command args will have this format.
  local note_path, count = string.gsub(query, "^.*  ", "")
  if count > 0 then
    local full_path = workspace_dir / note_path
    finish { Note.from_file(full_path, parse_opts) }
    return handle
  end

  -- Query might be a path.
  local fname = query
  if not vim.endswith(fname, ".md") and not vim.endswith(fname, ".qmd") and not vim.endswith(fname, ".base") then
    fname = fname .. ".md"
  end

  local paths_lookup = setmetatable({}, {
    __newindex = function(t, k, v)
      k = k:resolve()
      rawset(t, tostring(k), v) -- avoid duplicate
    end,
  })
  local paths_found = {}

  local buf_dir = opts.buf_dir or (opts.dir == nil and Obsidian.buf_dir or nil)
  if buf_dir ~= nil then
    local note_in_current_buf_dir = Path.new(buf_dir) / fname
    paths_lookup[note_in_current_buf_dir] = true
  end

  if Obsidian.opts.notes_subdir ~= nil then
    local note_in_notes_subdir = workspace_dir / Obsidian.opts.notes_subdir / fname
    paths_lookup[note_in_notes_subdir] = true
  end

  if Obsidian.opts.daily_notes.folder ~= nil then
    local notes_in_daily_notes_dir = workspace_dir / Obsidian.opts.daily_notes.folder / fname
    paths_lookup[notes_in_daily_notes_dir] = true
  end

  local note_with_absolute_path = Path.new(fname)
  local note_in_vault_root = workspace_dir / fname

  paths_lookup[note_with_absolute_path] = true
  paths_lookup[note_in_vault_root] = true

  for path in pairs(paths_lookup) do
    if Path.new(path):is_file() then
      paths_found[#paths_found + 1] = Note.from_file(path, parse_opts)
    end
  end

  if not vim.tbl_isempty(paths_found) then
    finish(paths_found)
    return handle
  end

  child = M.find_notes_async(query, function(results, err)
    if err then
      finish({}, err)
      return
    end
    local query_lwr = string.lower(query)

    -- `.base` files only resolve when the query explicitly names them.
    if not vim.endswith(query_lwr, ".base") then
      results = vim.tbl_filter(function(note)
        return not vim.endswith(tostring(note.path), ".base")
      end, results)
    end

    -- We'll gather both exact matches (of ID, filename, and aliases) and fuzzy matches.
    -- If we end up with any exact matches, we'll return those. Otherwise we fall back to fuzzy
    -- matches.
    ---@type obsidian.Note[]
    local exact_matches = {}
    ---@type obsidian.Note[]
    local fuzzy_matches = {}

    for _, note in ipairs(results) do
      ---@cast note obsidian.Note

      local reference_ids = note:reference_ids { lowercase = true }

      -- Check for exact match.
      if vim.list_contains(reference_ids, query_lwr) then
        table.insert(exact_matches, note)
      else
        -- TODO: use vim.fn.fuzzymatch
        -- Fall back to fuzzy match.
        for _, ref_id in ipairs(reference_ids) do
          if string.find(ref_id, query_lwr, 1, true) ~= nil then
            table.insert(fuzzy_matches, note)
            break
          end
        end
      end
    end

    if #exact_matches > 0 then
      finish(exact_matches)
    else
      finish(fuzzy_matches)
    end
  end, { dir = workspace_dir, collect = opts.collect })
  return handle
end

---@param query string
---@param opts { collect: obsidian.search.NoteCollectOpts|?, timeout: integer|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
---@return obsidian.Note[] notes
---@return string? err
M.resolve_note = function(query, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result, err = async.block_on(function(cb)
    return M.resolve_note_async(query, cb, { collect = opts.collect, dir = opts.dir, buf_dir = opts.buf_dir })
  end, opts.timeout)
  if result == nil then
    return {}, err or "note resolution timed out"
  end
  return result, err
end

---@param document obsidian.parse.Document
---@param ref obsidian.parse.Ref
---@return boolean
local function ref_is_eligible(document, ref)
  local origin = Range.new(ref.range.start_row, ref.range.start_col, ref.range.start_row, ref.range.start_col + 1)
  return not document:intersects(origin, Document.INLINE_EXCLUSIONS)
    and not document:intersects(ref.range, Document.COMMENTS)
end

---@param refs string[]
---@param anchor string|?
---@param block string|?
local function build_backlink_search_term(refs, anchor, block)
  -- Prepare search terms.
  local search_terms = {}

  for _, ref in ipairs(refs) do
    if anchor == nil and block == nil then
      -- Wiki links without anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s]]", ref)
      search_terms[#search_terms + 1] = string.format("[[%s|", ref)
      -- Markdown link without anchor/block.
      search_terms[#search_terms + 1] = string.format("](%s)", ref)
      -- Markdown link without anchor/block and is relative to root.
      search_terms[#search_terms + 1] = string.format("](/%s)", ref)
      search_terms[#search_terms + 1] = string.format("](./%s)", ref)
      -- Wiki links with anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s#", ref)
      -- Markdown link with anchor/block.
      search_terms[#search_terms + 1] = string.format("](%s#", ref)
      -- Markdown link with anchor/block and is relative to root.
      search_terms[#search_terms + 1] = string.format("](/%s#", ref)
    elseif anchor ~= nil then
      -- Note: Obsidian allow a lot of different forms of anchor links, so we can't assume
      -- it's the standardized form here.
      -- Wiki links with anchor.
      search_terms[#search_terms + 1] = string.format("[[%s#", ref)
      -- Markdown link with anchor.
      search_terms[#search_terms + 1] = string.format("](%s#", ref)
      -- Markdown link with anchor and is relative to root.
      search_terms[#search_terms + 1] = string.format("](/%s#", ref)
      search_terms[#search_terms + 1] = string.format("](./%s#", ref)
    elseif block ~= nil then
      -- Wiki links with block.
      search_terms[#search_terms + 1] = string.format("[[%s#%s", ref, block)
      -- Markdown link with block.
      search_terms[#search_terms + 1] = string.format("](%s#%s", ref, block)
      -- Markdown link with block and is relative to root.
      search_terms[#search_terms + 1] = string.format("](/%s#%s", ref, block)
      search_terms[#search_terms + 1] = string.format("](./%s#%s", ref, block)
    end
  end

  return search_terms
end

---@param term string
local function build_in_note_search_term(term)
  local terms = {}

  if vim.startswith(term, "#") then
    term = term:sub(2)
  end

  -- Wiki links with block.
  terms[#terms + 1] = string.format("[[#%s", term)
  -- Markdown link with block.
  terms[#terms + 1] = string.format("](#%s", term)
  -- Markdown link with block and is relative to root.
  terms[#terms + 1] = string.format("](/#%s", term)
  terms[#terms + 1] = string.format("](./#%s", term)

  return terms
end

---@param note obsidian.Note
---@return obsidian.BacklinkMatch[]
local function get_in_note_backlink(note, term)
  local matches = {}

  if not term then
    return matches
  end

  local patterns = build_in_note_search_term(term)
  local document = Document.parse(note.raw_contents or note.contents or {})

  for lnum, line in ipairs(note.contents or {}) do
    local matched = false
    for _, pat in ipairs(patterns) do
      local start_col = line:find(pat, 1, true)
      while start_col do
        local range = Range.new(lnum - 1, start_col - 1, lnum - 1, start_col - 1 + #pat)
        if not document:intersects(range, Document.INLINE_EXCLUSIONS) then
          matched = true
          break
        end
        start_col = line:find(pat, start_col + #pat, true)
      end
      if matched then
        break
      end
    end
    if matched then
      matches[#matches + 1] = {
        path = tostring(note.path),
        line = lnum,
        start = 0,
        ["end"] = 0,
      }
    end
  end
  return matches
end

---@param note obsidian.Note|?
---@param callback fun(matches: obsidian.BacklinkMatch[], err: string?)
---@param opts { anchor: string|?, block: string|?, dir: string|obsidian.Path|?, refs: string[]|? }|?
---@return obsidian.search.AsyncHandle
M.find_backlinks_async = function(note, callback, opts)
  -- vim.validate("note", note, "table")
  -- vim.validate("callback", callback, "function")
  local cancelled = false
  local scheduled_callback = vim.schedule_wrap(function(...)
    if not cancelled then
      callback(...)
    end
  end)
  opts = opts or {}
  local dir = opts.dir or (note and api.resolve_workspace_dir(note.path)) or api.resolve_workspace_dir()
  local block = opts.block and block_id.normalize(opts.block) or nil
  local anchor = opts.anchor and header.normalize_anchor(opts.anchor) or nil
  local anchor_obj
  if anchor and note then
    anchor_obj = note:resolve_anchor_link(anchor)
  end
  ---@type obsidian.BacklinkMatch[]
  local results = {}
  ---@type table<string, obsidian.parse.Document>
  local documents = {}

  if note then
    vim.list_extend(results, get_in_note_backlink(note, block or anchor))
  end

  ---@param submatches obsidian.search.SubMatch[]
  ---@param ref_start integer
  ---@param ref_end integer
  ---@return boolean
  local function _submatch_in_ref(submatches, ref_start, ref_end)
    for _, submatch in ipairs(submatches) do
      -- Convert 0-indexed submatch positions to 1-indexed for comparison
      local submatch_start_1idx = submatch.start + 1
      local submatch_end_1idx = submatch["end"]
      if submatch_start_1idx >= ref_start and submatch_end_1idx <= ref_end then
        return true
      end
    end
    return false
  end

  ---@param match obsidian.search.MatchData
  local _on_match = function(match)
    local path = Path.new(match.path.text):resolve { strict = true }
    local path_key = tostring(path)
    local document = documents[path_key]
    if document == nil then
      local lines = {}
      for source_line in io.lines(path_key) do
        lines[#lines + 1] = source_line:gsub("\r$", "")
      end
      document = Document.parse(lines)
      documents[path_key] = document
    end
    local parse_refs = require "obsidian.parse.refs"
    local row = match.line_number - 1
    local line_text = document.lines[row + 1]
    if line_text == nil then
      return
    end
    for _, ref in ipairs(parse_refs.extract(line_text, { row = row, lexical = true })) do
      local ref_start_1idx = ref.range.start_col + (ref.embed and 2 or 1)
      local ref_start = ref_start_1idx - 1
      local ref_end = ref.range.end_col
      if ref_is_eligible(document, ref) and _submatch_in_ref(match.submatches, ref_start_1idx, ref_end) then
        local matched_anchor = ref.block and ("#^" .. ref.block) or (ref.anchor and ("#" .. ref.anchor) or nil)
        local include = true
        if anchor and note then
          if not matched_anchor then
            include = false
          else
            local std_matched = header.normalize_anchor(matched_anchor)
            local is_direct_match = std_matched == anchor
            local is_resolved_match = false
            if not is_direct_match and anchor_obj ~= nil then
              local resolved = note:resolve_anchor_link(matched_anchor)
              if resolved and resolved.header == anchor_obj.header then
                is_resolved_match = true
              end
            end
            if not (is_direct_match or is_resolved_match) then
              include = false
            end
          end
        end
        if block and include then
          if not matched_anchor or block_id.normalize(matched_anchor) ~= block then
            include = false
          end
        end
        if include then
          results[#results + 1] = {
            link = ref.embed and ref.raw:sub(2) or ref.raw,
            path = path,
            line = match.line_number,
            text = line_text,
            start = ref_start,
            ["end"] = ref_end,
          }
        end
      end
    end
  end

  local refs
  if note then
    refs = note:get_reference_paths { urlencode = true }
  else
    refs = opts.refs
  end

  if not refs then
    error "no valid refs for backlinks search"
  end

  local child = M.search_async(
    dir,
    build_backlink_search_term(refs, anchor, block),
    { fixed_strings = true, ignore_case = true },
    _on_match,
    function(code)
      if code > 1 then
        scheduled_callback(results, ("backlink search failed with exit code %d"):format(code))
      else
        scheduled_callback(results)
      end
    end
  )
  return Handle.new(function()
    cancelled = true
    Handle.cancel(child)
  end)
end

---@param note obsidian.Note
---@param opts { anchor: string?, block: string?, timeout: integer?, dir: string|obsidian.Path?, refs: string[]? }?
---@return obsidian.BacklinkMatch[] matches
---@return string? err
M.find_backlinks = function(note, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result, err = async.block_on(function(cb)
    return M.find_backlinks_async(
      note,
      cb,
      { anchor = opts.anchor, block = opts.block, dir = opts.dir, refs = opts.refs }
    )
  end, opts.timeout)
  if result == nil then
    return {}, err or "backlink search timed out"
  end
  return result, err
end

--- Find all tags starting with the given search term(s).
---
---@param term string|string[] The search term.
---@param opts { timeout: integer|?, dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
---@return obsidian.TagLocation[] tags
---@return string? err
M.find_tags = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result, err = async.block_on(function(cb)
    return M.find_tags_async(term, cb, { dir = opts.dir, match = opts.match })
  end, opts.timeout)
  if result == nil then
    return {}, err or "tag search timed out"
  end
  return result, err
end

--- An async version of 'find_tags()'.
---
---@param term string|string[] The search term.
---@param callback fun(tags: obsidian.TagLocation[], err: string?)
---@param opts { dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
---@return obsidian.search.AsyncHandle
M.find_tags_async = function(term, callback, opts)
  local cancelled = false
  local scheduled_callback = vim.schedule_wrap(function(...)
    if not cancelled then
      callback(...)
    end
  end)
  opts = opts or {}

  local Note = require "obsidian.note"

  ---@type string[]
  local input_terms
  if type(term) == "string" then
    input_terms = { term }
  else
    input_terms = term
  end
  local terms = {}
  local terms_seen = {}
  for _, input_term in ipairs(input_terms) do
    local normalized = tags.normalize(input_term)
    if not terms_seen[normalized] then
      terms[#terms + 1] = normalized
      terms_seen[normalized] = true
    end
  end

  terms = compat.list_unique(terms)

  -- Maps paths to tag locations.
  ---@type table<string, obsidian.TagLocation[]>
  local path_to_tag_loc = {}
  local processed_paths = {}
  local err_count = 0
  local first_err = nil
  local first_err_path = nil

  ---@param occurrence obsidian.TagOccurrence
  ---@return boolean
  local include_occurrence = function(occurrence)
    for _, query in ipairs(terms) do
      if tags.matches(occurrence.tag, query, opts.match or "prefix") then
        return true
      end
    end
    return false
  end

  ---@param match_data obsidian.search.MatchData
  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve { strict = true }
    local path_key = tostring(path)
    if processed_paths[path_key] then
      return
    end
    processed_paths[path_key] = true

    local ok, note = pcall(Note.from_file, path)
    if not ok then
      err_count = err_count + 1
      if first_err == nil then
        first_err = note
        first_err_path = path
      end
      return
    end

    local locations = {}
    for _, occurrence in
      ipairs(tags.extract(note.raw_contents or note.contents, {
        frontmatter_end_line = note.frontmatter_end_line,
        frontmatter_elements = note.frontmatter_elements,
      }))
    do
      if include_occurrence(occurrence) then
        locations[#locations + 1] = {
          tag = occurrence.tag,
          path = path,
          note = note,
          line = occurrence.range.start_row + 1,
          text = occurrence.text,
          range = occurrence.range,
          tag_start = occurrence.range.start_col + 1,
          tag_end = occurrence.range.end_col,
        }
      end
    end
    if #locations > 0 then
      path_to_tag_loc[path_key] = locations
    end
  end

  -- Ripgrep only identifies candidate files. Parsed occurrences below decide
  -- whether a tag actually matches the query.
  local search_terms = {
    "#" .. TAG_CHARS_REQUIRED_RG,
    "^\\s*tags\\s*:",
  }

  local child = M.search_async(
    opts.dir or api.resolve_workspace_dir(),
    search_terms,
    { ignore_case = true, sort_by = false },
    on_match,
    function(code)
      if code > 1 then
        scheduled_callback({}, ("tag search failed with exit code %d"):format(code))
        return
      end
      ---@type obsidian.TagLocation[]
      local tags_list = {}

      local paths = vim.tbl_keys(path_to_tag_loc)
      table.sort(paths)
      for _, path in ipairs(paths) do
        for _, tag_loc in ipairs(path_to_tag_loc[path]) do
          tags_list[#tags_list + 1] = tag_loc
        end
      end

      -- Log any errors.
      if first_err ~= nil and first_err_path ~= nil then
        log.err(
          "%d error(s) occurred during search. First error from note at '%s':\n%s",
          err_count,
          first_err_path,
          first_err
        )
      end

      local err
      if first_err ~= nil then
        err = ("%d note(s) could not be parsed during tag search"):format(err_count)
      end
      scheduled_callback(tags_list, err)
    end
  )
  return Handle.new(function()
    cancelled = true
    Handle.cancel(child)
  end)
end

return M
