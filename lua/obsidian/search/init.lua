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
local SearchOpts = require "obsidian.search.opts"

local M = {}

local Filesystem = require "obsidian.search.filesystem"
local Ripgrep = require "obsidian.search.ripgrep"

local TAG_CHARS_REQUIRED_RG = [[[\p{L}\p{N}_/-]+[\p{L}\p{N}_/-]*[\p{L}_/-]+[\p{L}\p{N}_/-]*]]

--- Search markdown files in a directory for a given term. Each match is passed to the `on_match` callback.
---
---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.BackendOpts|?
---@param on_match fun(match: obsidian.search.MatchData)
---@param on_exit fun(exit_code: integer)|?
---@return vim.SystemObj
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
---@return fun() cancel
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
}

---@param method "find_notes"|"find_attachments"
---@param term string
---@param opts table
---@param callback fun(results: any[], unresolved: obsidian.search.Unresolved[]?)
local function dispatch_async(method, term, opts, callback)
  callback = vim.schedule_wrap(callback)
  if not cache_can_search(opts.dir) then
    filesystem_methods[method](term, callback, opts)
    return
  end

  local cache = require "obsidian.cache"
  cache.when_ready(function()
    local result = vim.F.pack_len(pcall(cache[method], term, opts))
    if result[1] then
      callback(unpack(result, 2, result.n))
    else
      log.err("Failed to find %s: %s", method == "find_notes" and "notes" or "attachments", result[2])
      callback {}
    end
  end)
end

---@param term string
---@param callback fun(notes: obsidian.Note[], unresolved: obsidian.search.Unresolved[]?)
---@param opts obsidian.search.FindNotesOpts|?
---@param domain obsidian.search.NoteSearchDomain
local function find_notes_by_domain_async(term, callback, opts, domain)
  ---@type obsidian.search.FindNotesBackendOpts
  local backend_opts = vim.tbl_extend("force", {}, opts or {})
  backend_opts.domain = domain
  backend_opts.dir = backend_opts.dir or api.resolve_workspace_dir()
  return dispatch_async("find_notes", term, backend_opts, callback)
end

---Find notes by references using the cache backend when possible, otherwise the filesystem backend.
---@param term string
---@param callback fun(notes: obsidian.Note[], unresolved: obsidian.search.Unresolved[]?)
---@param opts obsidian.search.FindNotesOpts|?
M.find_notes_async = function(term, callback, opts)
  return find_notes_by_domain_async(term, callback, opts, "references")
end

---Find notes whose references match a search term.
---@param term string
---@param opts obsidian.search.FindNotesOpts|?
---@return obsidian.Note[] notes
---@return obsidian.search.Unresolved[]? unresolved
M.find_notes = function(term, opts)
  opts = opts or {}
  local result, unresolved = async.block_on(function(cb)
    M.find_notes_async(term, cb, opts)
  end, opts.timeout or 3000)
  ---@cast result obsidian.Note[]?
  ---@cast unresolved obsidian.search.Unresolved[]?
  return result or {}, unresolved
end

---@generic T
---@param domain "headings"|"blocks"
---@param term string
---@param callback fun(matches: T[])
---@param opts obsidian.search.FindDomainOpts|?
local function find_domain_async(domain, term, callback, opts)
  opts = opts or {}
  local find_opts = {
    dir = opts.dir,
    sort_by = opts.sort_by,
    sort_reversed = opts.sort_reversed,
    ignore_case = opts.ignore_case,
  }
  local ignore_case = opts.ignore_case
  if ignore_case == nil then
    ignore_case = SearchOpts.should_ignore_case(term)
  end

  find_notes_by_domain_async(term, function(notes)
    ---@type T[]
    local matches = {}
    for _, note in ipairs(notes) do
      local note_matches
      if domain == "headings" then
        note_matches = note_matcher.matching_headings(note, term, ignore_case)
        for _, heading in ipairs(note_matches) do
          matches[#matches + 1] = { note = note, heading = heading }
        end
      else
        note_matches = note_matcher.matching_blocks(note, term, ignore_case)
        vim.list_extend(matches, note_matches)
      end
    end
    callback(matches)
  end, find_opts, domain)
end

---Find headings by their original text or normalized anchor.
---Each result contains the note and matching heading; results are ordered by note, then document position.
---@param term string
---@param callback fun(matches: obsidian.search.HeadingMatch[])
---@param opts obsidian.search.FindHeadingsOpts|?
M.find_headings_async = function(term, callback, opts)
  find_domain_async("headings", term, callback, opts)
end

---@param term string
---@param opts obsidian.search.FindHeadingsOpts|?
---@return obsidian.search.HeadingMatch[]
M.find_headings = function(term, opts)
  opts = opts or {}
  local result = async.block_on(function(cb)
    M.find_headings_async(term, cb, opts)
  end, opts.timeout or 3000)
  ---@cast result obsidian.search.HeadingMatch[]?
  return result or {}
end

---Find block candidates or explicit block identifiers by their text or ID.
---Each result contains the note, its matching section when available, and associated explicit blocks.
---@param term string
---@param callback fun(matches: obsidian.search.BlockMatch[])
---@param opts obsidian.search.FindBlocksOpts|?
M.find_blocks_async = function(term, callback, opts)
  find_domain_async("blocks", term, callback, opts)
end

---@param term string
---@param opts obsidian.search.FindBlocksOpts|?
---@return obsidian.search.BlockMatch[]
M.find_blocks = function(term, opts)
  opts = opts or {}
  local result = async.block_on(function(cb)
    M.find_blocks_async(term, cb, opts)
  end, opts.timeout or 3000)
  ---@cast result obsidian.search.BlockMatch[]?
  return result or {}
end

---Find attachment paths matching a filename or vault-relative path.
---@param term string
---@param callback fun(paths: string[], unresolved: obsidian.search.Unresolved[]?)
---@param opts obsidian.search.FindAttachmentsOpts|?
M.find_attachments_async = function(term, callback, opts)
  opts = opts or {}
  opts.dir = opts.dir or api.resolve_workspace_dir()
  return dispatch_async("find_attachments", term, opts, callback)
end

---@param term string
---@param opts obsidian.search.FindAttachmentsOpts|?
---@return string[] paths
---@return obsidian.search.Unresolved[]? unresolved
M.find_attachments = function(term, opts)
  opts = opts or {}
  local result, unresolved = async.block_on(function(cb)
    M.find_attachments_async(term, cb, opts)
  end, opts.timeout or 3000)
  ---@cast result string[]?
  ---@cast unresolved obsidian.search.Unresolved[]?
  return result or {}, unresolved
end

---@param query string
---@param callback fun(notes: obsidian.Note[])
---@param opts { dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
M.resolve_note_async = function(query, callback, opts)
  callback = vim.schedule_wrap(callback)
  opts = opts or {}
  local Note = require "obsidian.note"
  local workspace_dir = Path.new(opts.dir or api.resolve_workspace_dir())

  -- Autocompletion for command args will have this format.
  local note_path, count = string.gsub(query, "^.*  ", "")
  if count > 0 then
    local full_path = workspace_dir / note_path
    callback { Note.from_file(full_path) }
    return
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
      paths_found[#paths_found + 1] = Note.from_file(path)
    end
  end

  if not vim.tbl_isempty(paths_found) then
    callback(paths_found)
    return
  end

  M.find_notes_async(query, function(results)
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
      callback(exact_matches)
    else
      callback(fuzzy_matches)
    end
  end, { dir = workspace_dir, ignore_case = true })
end

---@param query string
---@param opts { timeout: integer|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
---@return obsidian.Note[] notes
M.resolve_note = function(query, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    M.resolve_note_async(query, cb, { dir = opts.dir, buf_dir = opts.buf_dir })
  end, opts.timeout)
  return result or {}
end

---Gather all unique links from a note.
---@param note obsidian.Note
---@return obsidian.LinkMatch[]
---@deprecated use `obsidian.Note:links()` instead. Will be removed in 4.0.0.
M.find_links = function(note)
  require("obsidian.util").deprecate("search.find_links", "Note:links()", "4.0.0")
  return note:links()
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
---@param callback fun(matches: obsidian.BacklinkMatch[])
---@param opts { anchor: string|?, block: string|?, dir: string|obsidian.Path|?, refs: string[]|? }|?
---@return vim.SystemObj
M.find_backlinks_async = function(note, callback, opts)
  -- vim.validate("note", note, "table")
  -- vim.validate("callback", callback, "function")
  callback = vim.schedule_wrap(callback)
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

  return M.search_async(
    dir,
    build_backlink_search_term(refs, anchor, block),
    { fixed_strings = true, ignore_case = true },
    _on_match,
    function()
      callback(results)
    end
  )
end

---@param note obsidian.Note
---@param opts { anchor: string?, block: string?, timeout: integer?, dir: string|obsidian.Path?, refs: string[]? }?
---@return obsidian.BacklinkMatch[] matches
M.find_backlinks = function(note, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    return M.find_backlinks_async(
      note,
      cb,
      { anchor = opts.anchor, block = opts.block, dir = opts.dir, refs = opts.refs }
    )
  end, opts.timeout)
  return result or {}
end

---Find unlinked plain-text mentions of other notes inside `note` ("outgoing" suggestions).
---
---@param note obsidian.Note
---@param opts { include_current: boolean?, range: obsidian.Range? }?
---@param callback fun(suggestions: obsidian.LinkSuggestion[])
M.find_link_suggestions_async = function(note, opts, callback)
  callback = vim.schedule_wrap(callback)
  callback(require("obsidian.note.link_suggestion").find(note, opts))
end

---@class obsidian.BacklinkSuggestion
---
---@field path string Path of the note containing the unlinked mention.
---@field suggestion obsidian.LinkSuggestion
---@field candidate obsidian.LinkSuggestionCandidate

---Scan a single note file for mentions of `symbols`.
---@param path string
---@param symbols obsidian.LinkSuggestionSymbol[]
---@param results obsidian.BacklinkSuggestion[]
local function scan_note_for_mentions(path, symbols, results)
  local link_suggestion = require "obsidian.note.link_suggestion"

  -- Fast pre-filter: check if any symbol text appears in the raw file before a full parse.
  local raw_file = io.open(path, "r")
  if not raw_file then
    return
  end
  local raw_content = raw_file:read("*a"):lower()
  raw_file:close()

  local has_candidate = false
  for _, sym in ipairs(symbols) do
    if raw_content:find(sym.text_lower, 1, true) then
      has_candidate = true
      break
    end
  end
  if not has_candidate then
    return
  end

  local ok_note, other_note = pcall(require("obsidian.note").from_file, path)
  if not ok_note or not other_note then
    return
  end

  local fm_end = other_note.frontmatter_end_line or 1
  local source_dir = vim.fs.dirname(vim.fs.normalize(path))
  local code_fence = nil

  local function path_exists(p)
    return vim.uv.fs_stat(p) ~= nil
  end

  for row = fm_end, #other_note.contents do
    local line = other_note.contents[row]
    ---@cast line string
    local fence = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
    if fence then
      if not code_fence then
        code_fence = fence
      elseif fence:sub(1, 1) == code_fence:sub(1, 1) and #fence >= #code_fence then
        code_fence = nil
      end
    elseif not code_fence then
      for _, suggestion in ipairs(link_suggestion.find_in_line(line, row, symbols, path_exists, source_dir)) do
        for _, candidate in ipairs(suggestion.candidates) do
          results[#results + 1] = { path = path, suggestion = suggestion, candidate = candidate }
        end
      end
    end
  end
end

---Find unlinked plain-text mentions of `note` (by title or alias) in other notes ("incoming" suggestions).
---Requires the cache to be enabled.
---
---@param note obsidian.Note
---@param opts { dir: string|obsidian.Path? }?
---@param callback fun(suggestions: obsidian.BacklinkSuggestion[])
M.find_backlinks_suggestions_async = function(note, opts, callback)
  opts = opts or {}
  callback = vim.schedule_wrap(callback)

  ---@type obsidian.BacklinkSuggestion[]
  local results = {}
  local cache = require "obsidian.cache"
  if not note.path or not cache.is_enabled() then
    return callback(results)
  end

  local current_path = vim.fs.normalize(tostring(note.path))
  local symbols = require("obsidian.note.link_suggestion").symbols_for_path(current_path)
  local ok, cached_rows = pcall(cache.notes.all)
  if #symbols == 0 or not ok or not cached_rows then
    return callback(results)
  end

  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)):gsub("/+$", "") or nil
  for path, _ in pairs(cached_rows) do
    local norm_path = vim.fs.normalize(path)
    if norm_path ~= current_path and (not dir or vim.startswith(norm_path, dir .. "/")) then
      scan_note_for_mentions(path, symbols, results)
    end
  end

  callback(results)
end

--- Find all tags starting with the given search term(s).
---
---@param term string|string[] The search term.
---@param opts { timeout: integer|?, dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
---@return obsidian.TagLocation[] tags
M.find_tags = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    M.find_tags_async(term, cb, { dir = opts.dir, match = opts.match })
  end, opts.timeout)
  return result or {}
end

--- An async version of 'find_tags()'.
---
---@param term string|string[] The search term.
---@param callback fun(tags: obsidian.TagLocation[])
---@param opts { dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
---@return vim.SystemObj
M.find_tags_async = function(term, callback, opts)
  callback = vim.schedule_wrap(callback)
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

  compat.list_unique(terms)

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

  return M.search_async(
    opts.dir or api.resolve_workspace_dir(),
    search_terms,
    { ignore_case = true, sort_by = false },
    on_match,
    function(code)
      if code > 1 then
        callback {}
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

      callback(tags_list)
    end
  )
end

return M
