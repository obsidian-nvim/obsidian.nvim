local Document = require "obsidian.parse.document"
local Path = require "obsidian.path"
local Range = require "obsidian.range"
local compat = require "obsidian.compat"
local header = require "obsidian.parse.header"
local block_id = require "obsidian.parse.block_id"
local log = require "obsidian.log"
local async = require "obsidian.async"
local fs = require "obsidian.fs"
local gitignore = require("obsidian.lib.glob").gitignore
local api = require "obsidian.api"
local tags = require "obsidian.tag"

local M = {}

---@param t table|function
local function iter(t)
  ---@diagnostic disable-next-line: call-non-callable
  return vim.iter(t)
end

local Opts = require "obsidian.search.opts" -- general class to handle options
local Ripgrep = require "obsidian.search.ripgrep" -- could have other backends in the future...

M.build_grep_cmd = Ripgrep.build_grep_cmd

M._has_ripgrep = function()
  return vim.fn.executable "rg" == 1
end

M.Patterns = {
  -- Tags
  TagCharsRequiredRg = [[[\p{L}\p{N}_/-]+[\p{L}\p{N}_/-]*[\p{L}_/-]+[\p{L}\p{N}_/-]*]],
  TagCharsOptionalRg = [[[\p{L}\p{N}_/-]*]],
}

--- Find inline highlights
---
---@param s string
---
---@return { [1]: integer, [2]: integer }[]
M.find_highlight = function(s)
  local matches = {}
  local search_start = 1
  while search_start < #s do
    local match_start, match_end = s:find("==[^=]+==", search_start)
    if not match_start or not match_end then
      break
    end

    -- Remove highlights that begin/end with whitespace.
    local text = s:sub(match_start + 2, match_end - 2)
    if vim.trim(text) == text then
      matches[#matches + 1] = { match_start, match_end }
    end

    search_start = match_end
  end
  return matches
end

---@class MatchPath
---
---@field text string

---@class MatchText
---
---@field text string

---@class SubMatch
---
---@field match MatchText
---@field start integer
---@field end integer

---@class MatchData
---
---@field path MatchPath
---@field lines MatchText
---@field line_number integer 0-indexed
---@field absolute_offset integer
---@field submatches SubMatch[]

--- Search markdown files in a directory for a given term. Each match is passed to the `on_match` callback.
---
---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.SearchOpts|?
---@param on_match fun(match: MatchData)
---@param on_exit fun(exit_code: integer)|?
---@return vim.SystemObj handle
M.search_async = function(dir, term, opts, on_match, on_exit)
  local cmd = Ripgrep.build_search_cmd(dir, term, opts)
  return async.run_job_async(cmd, function(line)
    local data = vim.json.decode(line)
    if data["type"] == "match" then
      local match_data = data.data
      on_match(match_data)
    end
  end, function(code)
    if on_exit ~= nil then
      on_exit(code)
    end
  end)
end

--- Find files in a directory matching a given term. Each matching path is
--- passed to the `on_match` callback.
---
---@param dir string|obsidian.Path
---@param term string?
---@param opts obsidian.search.SearchOpts|?
---@param on_match fun(path: string)
---@param on_exit fun(exit_code: integer)|?
---@return fun() cancel
M.find_async = function(dir, term, opts, on_match, on_exit)
  local norm_dir = Path.new(dir):resolve { strict = true }
  opts = vim.deepcopy(opts or {})
  local workspace = Obsidian and api.find_workspace(norm_dir) or nil

  if workspace then
    local workspace_opts = api._workspace_opts(workspace)
    local ignore_filters = workspace_opts.file and workspace_opts.file.ignore_filters or {}
    opts.exclude = opts.exclude or {}
    for _, pattern in ipairs(ignore_filters) do
      if not vim.tbl_contains(opts.exclude, pattern) then
        opts.exclude[#opts.exclude + 1] = pattern
      end
    end
  end

  local query = term and string.lower(term) or nil
  local exclude = opts.exclude and gitignore(opts.exclude, { ignoreCase = true }) or nil
  local markdown_extensions = { [".md"] = true, [".qmd"] = true, [".base"] = true }

  local cancelled = false
  local cancel_backend

  local function finish(paths, code)
    if cancelled then
      return
    end
    for _, path in ipairs(paths) do
      on_match(vim.fs.normalize(path))
    end
    if on_exit ~= nil then
      on_exit(code)
    end
  end

  local function find_with_fs()
    cancel_backend = fs.find_files_async(norm_dir, {
      sort_by = opts.sort_by,
      sort_reversed = opts.sort_reversed,
      ignore = function(path)
        if not exclude then
          return false
        end
        local relative_path = tostring(Path.new(path):relative_to(norm_dir))
        return exclude:check(relative_path)
      end,
      predicate = function(path)
        local extension = "." .. vim.fn.fnamemodify(path, ":e"):lower()
        if not opts.include_non_markdown and not markdown_extensions[extension] then
          return false
        end
        return not query or string.find(string.lower(vim.fs.basename(path)), query, 1, true) ~= nil
      end,
    }, function(paths)
      finish(paths, 0)
    end)
  end

  if M._has_ripgrep() then
    local handle = vim.system(Ripgrep.build_find_cmd(tostring(norm_dir), opts), { text = true }, function(result)
      vim.schedule(function()
        if cancelled then
          return
        elseif result.code ~= 0 then
          find_with_fs()
          return
        end

        local paths = iter(vim.split(result.stdout or "", "\n", { plain = true, trimempty = true }))
          :filter(function(path)
            if query then
              return string.find(string.lower(vim.fs.basename(path)), query, 1, true) ~= nil
            else
              return true
            end
          end)
          :totable()

        finish(paths, result.code)
      end)
    end)
    cancel_backend = function()
      handle:kill(15)
    end
  else
    find_with_fs()
  end

  return function()
    cancelled = true
    if cancel_backend then
      cancel_backend()
    end
  end
end

---@param term string
---@param dir string|obsidian.Path
---@param search_opts obsidian.SearchOpts
---@param find_opts obsidian.SearchOpts
---@param callback fun(path: obsidian.Path)
---@param exit_callback fun(paths: obsidian.Path[])
local _search_async = function(term, dir, search_opts, find_opts, callback, exit_callback)
  local found = {}
  local result = {}
  local cmds_done = 0
  dir = dir or api.resolve_workspace_dir()

  local function dedup_send(path)
    local key = tostring(path:resolve { strict = true })
    if not found[key] then
      found[key] = true
      result[#result + 1] = path
      callback(path)
    end
  end

  local function on_search_match(content_match)
    local path = Path.new(content_match.path.text)
    dedup_send(path)
  end

  local function on_find_match(path_match)
    local path = Path.new(path_match)
    dedup_send(path)
  end

  local function on_exit()
    cmds_done = cmds_done + 1
    if cmds_done == 2 then
      exit_callback(result)
    end
  end

  M.search_async(
    dir,
    term,
    Opts._prepare(search_opts, { fixed_strings = true, max_count_per_file = 1 }),
    on_search_match,
    on_exit
  )

  M.find_async(dir, term, Opts._prepare(find_opts, { ignore_case = true }), on_find_match, on_exit)
end

--- An async version of `find_notes()` using coroutines.
---
---@param term string The term to search for
---@param callback fun(notes: obsidian.Note[])
---@param opts { search: obsidian.SearchOpts|?, notes: obsidian.note.LoadOpts|?, dir: obsidian.Path|? }|?
M.find_notes_async = function(term, callback, opts)
  callback = vim.schedule_wrap(callback)
  async.run(function()
    opts = opts or {}
    opts.notes = opts.notes or {}
    if not opts.notes.max_lines then
      opts.notes.max_lines = Obsidian.opts.search.max_lines
    end

    local Note = require "obsidian.note"

    ---@type table<string, integer>
    local paths = {}
    local num_results = 0
    local err_count = 0
    local first_err, first_err_path
    local notes = {}

    -- Awaitable wrapper for loading a single note from path
    ---@param path string
    local function load_note_async(path)
      local ok, res = pcall(Note.from_file, path, opts.notes)
      if ok then
        num_results = num_results + 1
        paths[tostring(path)] = num_results
        notes[#notes + 1] = res
      else
        err_count = err_count + 1
        if not first_err then
          first_err = res
          first_err_path = path
        end
      end
    end

    local paths_found = {} ---@type string[]
    async.await(6, _search_async, term, opts.dir, opts.search, nil, function(path)
      paths_found[#paths_found + 1] = path
    end)

    async.join(
      10,
      vim.tbl_map(function(path)
        return function()
          load_note_async(path)
        end
      end, paths_found)
    )

    -- Sort notes by search order
    table.sort(notes, function(a, b)
      return paths[tostring(a.path)] < paths[tostring(b.path)]
    end)

    -- Report any errors
    if first_err ~= nil and first_err_path ~= nil then
      log.err(
        "%d error(s) occurred during search. First error from note at '%s':\n%s",
        err_count,
        first_err_path,
        first_err
      )
    end

    callback(notes)
  end)
end

--- Find notes matching search term.
---
--- Synchronous wrapper retained for Vim callbacks that must return synchronously
--- (`includeexpr`, command-completion `customlist` functions).
---
---@param term string The term to search for
---@param opts { search: obsidian.SearchOpts|?, notes: obsidian.note.LoadOpts|?, dir: obsidian.Path|?, timeout: integer|? }
---@return obsidian.Note[] notes always returns a list (empty on timeout)
M.find_notes = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    M.find_notes_async(term, cb, { search = opts.search, notes = opts.notes })
  end, opts.timeout)
  ---@cast result obsidian.Note[]?
  return result or {}
end

-- TODO: filter blocks and anchors in here, see _definition, but how does it interact with the shortcut stuff?

---@param query string
---@param callback fun(notes: obsidian.Note[])
---@param opts { notes: obsidian.note.LoadOpts|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
M.resolve_note_async = function(query, callback, opts)
  callback = vim.schedule_wrap(callback)
  opts = opts or {}
  opts.notes = opts.notes or {}
  if not opts.notes.max_lines then
    opts.notes.max_lines = Obsidian.opts.search.max_lines
  end
  local Note = require "obsidian.note"
  local workspace_dir = Path.new(opts.dir or api.resolve_workspace_dir())

  -- Autocompletion for command args will have this format.
  local note_path, count = string.gsub(query, "^.*  ", "")
  if count > 0 then
    local full_path = workspace_dir / note_path
    callback { Note.from_file(full_path, opts.notes) }
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
      paths_found[#paths_found + 1] = Note.from_file(path, opts.notes)
    end
  end

  if not vim.tbl_isempty(paths_found) then
    return callback(paths_found)
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
  end, { dir = workspace_dir, search = { ignore_case = true }, notes = opts.notes })
end

---@param query string
---@param opts { notes: obsidian.note.LoadOpts|?, timeout: integer|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }|?
---@return obsidian.Note[]
M.resolve_note = function(query, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    M.resolve_note_async(query, cb, { notes = opts.notes, dir = opts.dir, buf_dir = opts.buf_dir })
  end, opts.timeout)
  ---@cast result obsidian.Note[]?
  return result or {}
end

---@param document obsidian.parse.Document
---@param ref obsidian.parse.Ref
---@return boolean
local function ref_is_eligible(document, ref)
  local origin = Range.new(ref.range.start_row, ref.range.start_col, ref.range.start_row, ref.range.start_col + 1)
  return not document:intersects(origin, Document.BODY_EXCLUSIONS)
    and not document:intersects(ref.range, Document.COMMENTS)
end

---@class obsidian.LinkMatch
---@field link string
---@field line integer
---@field start integer 0-indexed
---@field end integer 0-indexed

-- Gather all unique links from the a note.
--
---@param note obsidian.Note
---@return obsidian.LinkMatch[]
M.find_links = function(note)
  local matches = {}
  ---@type table<string, boolean>
  local found = {}
  local lines = {}
  for line in io.lines(tostring(note.path)) do
    lines[#lines + 1] = line:gsub("\r$", "")
  end
  local document = Document.parse(lines)

  local parse_refs = require "obsidian.parse.refs"
  for lnum, line in ipairs(lines) do
    for _, ref in ipairs(parse_refs.extract(line, { row = lnum - 1, lexical = true })) do
      local link = ref.embed and ref.raw:sub(2) or ref.raw
      if ref_is_eligible(document, ref) and not found[link] then
        local match = {
          link = link,
          line = lnum,
          start = ref.range.start_col + (ref.embed and 1 or 0),
          ["end"] = ref.range.end_col - 1,
        }
        matches[#matches + 1] = match
        found[link] = true
      end
    end
  end

  return matches
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

M._build_backlink_search_term = build_backlink_search_term

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
        if not document:intersects(range, Document.BODY_EXCLUSIONS) then
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

---@class obsidian.BacklinkMatch
---
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.
---@field start integer|? The start of match (0-indexed)
---@field end integer|? The end of match (0-indexed)
---@field link string actual matched link text

---@param note obsidian.Note|?
---@param callback fun(matches: obsidian.BacklinkMatch[])
---@param opts { search: obsidian.SearchOpts|?, anchor: string|?, block: string|?, dir: string|obsidian.Path|?, refs: string[]|? }|?
---@return vim.SystemObj handle
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

  ---@param submatches SubMatch[]
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

  ---@param match MatchData
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
---@param opts { search: obsidian.SearchOpts?, anchor: string?, block: string?, timeout: integer?, dir: string|obsidian.Path?, refs: string[]? }?
---@return obsidian.BacklinkMatch[] matches always returns a list (empty on timeout)
M.find_backlinks = function(note, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    return M.find_backlinks_async(
      note,
      cb,
      { search = opts.search, anchor = opts.anchor, block = opts.block, dir = opts.dir, refs = opts.refs }
    )
  end, opts.timeout)
  ---@cast result obsidian.BacklinkMatch[]?
  return result or {}
end

---@class obsidian.TagLocation
---
---@field tag string The tag found.
---@field note obsidian.Note The note instance where the tag was found.
---@field path string|obsidian.Path The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field text string The original source line where the tag was found.
---@field range obsidian.Range The exact source range of the tag.
---@field tag_start integer The 1-based byte column where the tag starts.
---@field tag_end integer The 1-based exclusive byte column where the tag ends.

--- Find all tags starting with the given search term(s).
---
---@param term string|string[] The search term.
---@param opts { search: obsidian.SearchOpts|?, timeout: integer|?, dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
---@return obsidian.TagLocation[] tags always returns a list (empty on timeout)
M.find_tags = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  local result = async.block_on(function(cb)
    M.find_tags_async(term, cb, { search = opts.search, dir = opts.dir, match = opts.match })
  end, opts.timeout)
  ---@cast result obsidian.TagLocation[]?
  return result or {}
end

--- An async version of 'find_tags()'.
---
---@param term string|string[] The search term.
---@param callback fun(tags: obsidian.TagLocation[])
---@param opts { search: obsidian.SearchOpts|?, dir: obsidian.Path|?, match: "exact"|"subtree"|"prefix"|? }|?
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

  ---@param match_data MatchData
  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve { strict = true }
    local path_key = tostring(path)
    if processed_paths[path_key] then
      return
    end
    processed_paths[path_key] = true

    local ok, note = pcall(Note.from_file, path, {
      load_contents = true,
      max_lines = Obsidian.opts.search.max_lines,
    })
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
    "#" .. M.Patterns.TagCharsRequiredRg,
    "^\\s*tags\\s*:",
  }

  M.search_async(
    opts.dir or api.resolve_workspace_dir(),
    search_terms,
    Opts._prepare(opts.search, { ignore_case = true }),
    on_match,
    function(code)
      if code ~= 0 then
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
