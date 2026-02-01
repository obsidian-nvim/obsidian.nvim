local Path = require "obsidian.path"
local util = require "obsidian.util"
local log = require "obsidian.log"
local async = require "obsidian.async"

local M = {}

local Opts = require "obsidian.search.opts" -- general class to handle options
local Ripgrep = require "obsidian.search.ripgrep" -- could have other backends in the future...

M.build_find_cmd = Ripgrep.build_find_cmd
M.build_search_cmd = Ripgrep.build_search_cmd
M.build_grep_cmd = Ripgrep.build_grep_cmd

---@alias obsidian.search.RefTypes
---| "Wiki"
---| "WikiWithAlias"
---| "Markdown"
---| "Tag"
---| "BlockID"
---| "Highlight"
---| "HeaderLink"
---| "BlockLink"

M.Patterns = {
  -- Tags
  TagCharsOptional = "[A-Za-z0-9_/-]*",
  TagCharsRequired = "[A-Za-z]+[A-Za-z0-9_/-]*[A-Za-z0-9]+", -- assumes tag is at least 2 chars
  Tag = "#[A-Za-z]+[A-Za-z0-9_/-]*[A-Za-z0-9]+",

  -- Miscellaneous
  Highlight = "==[^=]+==", -- ==text==

  -- References
  WikiWithAlias = "%[%[[^][%|]+%|[^%]]+%]%]", -- [[xxx|yyy]]
  Wiki = "%[%[[^][%|]+%]%]", -- [[xxx]]
  Markdown = "%[[^][]+%]%([^%)]+%)", -- [yyy](xxx)
  BlockID = util.BLOCK_PATTERN .. "$", -- ^hello-world
}

---@type table<obsidian.search.RefTypes, { ignore_if_escape_prefix: boolean|? }>
M.PatternConfig = {
  Tag = { ignore_if_escape_prefix = true },
}

--- Find all matches of a pattern
---
---@param s string
---@param pattern_names obsidian.search.RefTypes[]
---
---@return { [1]: integer, [2]: integer, [3]: obsidian.search.RefTypes }[]
M.find_matches = function(s, pattern_names)
  -- First find all inline code blocks so we can skip reference matches inside of those.
  local inline_code_blocks = {}
  for m_start, m_end in util.gfind(s, "`[^`]*`") do
    inline_code_blocks[#inline_code_blocks + 1] = { m_start, m_end }
  end

  local matches = {}
  for _, pattern_name in ipairs(pattern_names) do
    local pattern = M.Patterns[pattern_name]
    local pattern_cfg = M.PatternConfig[pattern_name]
    local search_start = 1
    while search_start < #s do
      local m_start, m_end = string.find(s, pattern, search_start)
      if m_start ~= nil and m_end ~= nil then
        -- Check if we're inside a code block.
        local inside_code_block = false
        for _, code_block_boundary in ipairs(inline_code_blocks) do
          if code_block_boundary[1] < m_start and m_end < code_block_boundary[2] then
            inside_code_block = true
            break
          end
        end

        if not inside_code_block then
          -- Check if this match overlaps with any others (e.g. a naked URL match would be contained in
          -- a markdown URL).
          local overlap = false
          for _, match in ipairs(matches) do
            if (match[1] <= m_start and m_start <= match[2]) or (match[1] <= m_end and m_end <= match[2]) then
              overlap = true
              break
            end
          end

          -- Check if we should skip to an escape sequence before the pattern.
          local skip_due_to_escape = false
          if
            pattern_cfg ~= nil
            and pattern_cfg.ignore_if_escape_prefix
            and string.sub(s, m_start - 1, m_start - 1) == [[\]]
          then
            skip_due_to_escape = true
          end

          if not overlap and not skip_due_to_escape then
            matches[#matches + 1] = { m_start, m_end, pattern_name }
          end
        end

        search_start = m_end
      else
        break
      end
    end
  end

  -- Sort results by position.
  table.sort(matches, function(a, b)
    return a[1] < b[1]
  end)

  return matches
end

--- Find inline highlights
---
---@param s string
---
---@return { [1]: integer, [2]: integer, [3]: obsidian.search.RefTypes }[]
M.find_highlight = function(s)
  local matches = {}
  for _, match in ipairs(M.find_matches(s, { "Highlight" })) do
    -- Remove highlights that begin/end with whitespace
    local match_start, match_end, _ = unpack(match)
    local text = string.sub(s, match_start + 2, match_end - 2)
    if vim.trim(text) == text then
      matches[#matches + 1] = match
    end
  end
  return matches
end

--- Find refs and URLs.
---@param s string the string to search
---@param opts? { exclude: obsidian.search.RefTypes[] }
---
---@return { [1]: integer, [2]: integer, [3]: obsidian.search.RefTypes }[]
M.find_refs = function(s, opts)
  opts = opts and opts or {}

  local exclude_lookup = { ["Highlight"] = true }
  local pattern_names = {}

  for _, ref_type in ipairs(opts.exclude or {}) do
    exclude_lookup[ref_type] = true
  end

  ---@type obsidian.search.RefTypes[]
  local parse_patterns = {
    "WikiWithAlias",
    "Wiki",
    "Markdown",
    "Tag",
    "BlockID",
    "Highlight",
  }

  for _, ref_type in ipairs(parse_patterns) do
    if not exclude_lookup[ref_type] then
      pattern_names[#pattern_names + 1] = ref_type
    end
  end

  return M.find_matches(s, pattern_names)
end

-- Finds the correct link in a line given a grep position
---@param line string
---@param match_start integer
---@param match_end integer
---@return string|nil, obsidian.search.RefTypes|nil
M.find_ref_at_position = function(line, match_start, match_end)
  for _, ref in ipairs(M.find_refs(line, { exclude = { "Tag" } })) do
    local ref_start, ref_end, ref_type = unpack(ref)

    if ref_start <= match_end and ref_end >= match_start then
      return line:sub(ref_start, ref_end), ref_type
    end
  end

  return nil
end

--- Find all code block boundaries in a list of lines.
---
---@param lines string[]
---
---@return { [1]: integer, [2]: integer }[]
M.find_code_blocks = function(lines)
  ---@type { [1]: integer, [2]: integer }[]
  local blocks = {}
  ---@type integer|?
  local start_idx
  for i, line in ipairs(lines) do
    if string.match(line, "^%s*```.*```%s*$") then
      table.insert(blocks, { i, i })
      start_idx = nil
    elseif string.match(line, "^%s*```") then
      if start_idx ~= nil then
        table.insert(blocks, { start_idx, i })
        start_idx = nil
      else
        start_idx = i
      end
    end
  end
  return blocks
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
M.search_async = function(dir, term, opts, on_match, on_exit)
  local cmd = M.build_search_cmd(dir, term, opts)
  async.run_job_async(cmd, function(line)
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

--- Find markdown files in a directory matching a given term. Each matching path is passed to the `on_match` callback.
---
---@param dir string|obsidian.Path
---@param term string
---@param opts obsidian.search.SearchOpts|?
---@param on_match fun(path: string)
---@param on_exit fun(exit_code: integer)|?
M.find_async = function(dir, term, opts, on_match, on_exit)
  local norm_dir = Path.new(dir):resolve { strict = true }
  local cmd = M.build_find_cmd(tostring(norm_dir), term, opts)
  async.run_job_async(cmd, on_match, function(code)
    if on_exit ~= nil then
      on_exit(code)
    end
  end)
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
  dir = dir or Obsidian.dir

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

M.find_notes = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  return async.block_on(function(cb)
    return M.find_notes_async(term, cb, { search = opts.search })
  end, opts.timeout)
end

---@param query string
---@param opts { notes: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note[]
M.resolve_note = function(query, opts)
  opts = opts or {}
  opts.notes = opts.notes or {}
  if not opts.notes.max_lines then
    opts.notes.max_lines = Obsidian.opts.search.max_lines
  end
  local Note = require "obsidian.note"

  -- Autocompletion for command args will have this format.
  local note_path, count = string.gsub(query, "^.*  ", "")
  if count > 0 then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    local full_path = Obsidian.dir / note_path
    return { Note.from_file(full_path, opts.notes) }
  end

  -- Query might be a path.
  local fname = query
  if not vim.endswith(fname, ".md") then
    fname = fname .. ".md"
  end

  local paths_lookup = setmetatable({}, {
    __newindex = function(t, k, v)
      k = k:resolve()
      rawset(t, tostring(k), v) -- avoid duplicate
    end,
  })
  local paths_found = {}

  if Obsidian.buf_dir ~= nil then
    local note_in_current_buf_dir = Obsidian.buf_dir / fname
    paths_lookup[note_in_current_buf_dir] = true
  end

  if Obsidian.opts.notes_subdir ~= nil then
    local note_in_notes_subdir = Obsidian.dir / Obsidian.opts.notes_subdir / fname
    paths_lookup[note_in_notes_subdir] = true
  end

  if Obsidian.opts.daily_notes.folder ~= nil then
    local notes_in_daily_notes_dir = Obsidian.dir / Obsidian.opts.daily_notes.folder / fname
    paths_lookup[notes_in_daily_notes_dir] = true
  end

  local note_with_absolute_path = Path.new(fname)
  local note_in_vault_root = Obsidian.dir / fname

  paths_lookup[note_with_absolute_path] = true
  paths_lookup[note_in_vault_root] = true

  for path in pairs(paths_lookup) do
    if Path.new(path):is_file() then
      paths_found[#paths_found + 1] = Note.from_file(path, opts.notes)
    end
  end

  if not vim.tbl_isempty(paths_found) then
    return paths_found
  end

  local results = M.find_notes(query, { search = { sort = true, ignore_case = true }, notes = opts.notes })
  local query_lwr = string.lower(query)

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
    return exact_matches
  else
    return fuzzy_matches
  end
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
  local lines = io.lines(tostring(note.path))

  for lnum, line in vim.iter(lines):enumerate() do
    for _, ref_match in ipairs(M.find_refs(line, { exclude = { "BlockID", "Tag" } })) do
      local m_start, m_end = unpack(ref_match)
      local link = string.sub(line, m_start, m_end)
      if not found[link] then
        local match = {
          link = link,
          line = lnum,
          start = m_start - 1,
          ["end"] = m_end - 1,
        }
        matches[#matches + 1] = match
        found[link] = true
      end
    end
  end

  return matches
end

---@param note obsidian.Note
---@param anchor string
---@param block string
local function build_backlink_search_term(note, anchor, block)
  -- Prepare search terms.
  local search_terms = {}
  local raw_refs = note:get_reference_paths { urlencode = true }

  for _, ref in ipairs(raw_refs) do
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

  for alias in vim.iter(note.aliases) do
    if anchor == nil and block == nil then
      -- Wiki link without anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s]]", alias)
      -- Wiki link with anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif anchor ~= nil then
      -- Wiki link with anchor.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif block ~= nil then
      -- Wiki link with block.
      search_terms[#search_terms + 1] = string.format("[[%s#%s", alias, block)
    end
  end
  return search_terms
end

M._build_backlink_search_term = build_backlink_search_term

---@param term string
local function build_in_note_search_term(term)
  local terms = {}

  if vim.startswith(term, "#") then
    term = term:sub(2) -- NOTE: should be done in standardize_anchor
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

  for lnum, line in ipairs(note.contents or {}) do
    for _, pat in ipairs(patterns) do
      if string.find(line, pat, 1, true) ~= nil then
        matches[#matches + 1] = {
          path = tostring(note.path),
          line = lnum,
          start = 0,
          ["end"] = 0,
        }
      end
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

---@param note obsidian.Note
---@param callback fun(matches: obsidian.BacklinkMatch[])
---@param opts { search: obsidian.SearchOpts, on_match: fun(match: obsidian.BacklinkMatch), anchor: string, block: string, dir: string|obsidian.Path }
M.find_backlinks_async = function(note, callback, opts)
  -- vim.validate("note", note, "table")
  -- vim.validate("callback", callback, "function")
  opts = opts or {}
  local dir = opts.dir or Obsidian.dir
  local block = opts.block and util.standardize_block(opts.block) or nil
  local anchor = opts.anchor and util.standardize_anchor(opts.anchor) or nil
  local anchor_obj
  if anchor then
    anchor_obj = note:resolve_anchor_link(anchor)
  end
  ---@type obsidian.BacklinkMatch[]
  local results = {}

  vim.list_extend(results, get_in_note_backlink(note, block or anchor))

  ---@param match MatchData

  local _on_match = function(match)
    local path = Path.new(match.path.text):resolve { strict = true }
    local line_text = util.rstrip_whitespace(match.lines.text)
    for _, ref in ipairs(M.find_refs(line_text)) do
      local ref_start, ref_end, ref_type = unpack(ref)
      local ref_text = line_text:sub(ref_start, ref_end)
      local link_location, _, _ = util.parse_link(ref_text, { link_type = ref_type })
      if link_location then
        local include = true
        if anchor then
          local _, matched_anchor = util.strip_anchor_links(link_location)
          if not matched_anchor or matched_anchor:lower() ~= anchor:lower() then
            include = false
          end
        end
        if block and include then
          local _, matched_anchor = util.strip_anchor_links(link_location)
          if util.standardize_block(matched_anchor) ~= block then
            include = false
          end
        end
        if include then
          results[#results + 1] = {
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

  M.search_async(
    dir,
    build_backlink_search_term(note, anchor, block),
    { fixed_strings = true, ignore_case = true },
    _on_match,
    function()
      callback(results)
    end
  )
end

---@param note obsidian.Note
---@param opts { search: obsidian.SearchOpts, anchor: string, block: string, timeout: integer, dir: string|obsidian.Path }?
---@return obsidian.BacklinkMatch
M.find_backlinks = function(note, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  return async.block_on(function(cb)
    return M.find_backlinks_async(
      note,
      cb,
      { search = opts.search, anchor = opts.anchor, block = opts.block, dir = opts.dir }
    )
  end, opts.timeout)
end

---@class obsidian.TagLocation
---
---@field tag string The tag found.
---@field note obsidian.Note The note instance where the tag was found.
---@field path string|obsidian.Path The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field text string The text (with whitespace stripped) of the line where the tag was found.
---@field tag_start integer|? The index within 'text' where the tag starts.
---@field tag_end integer|? The index within 'text' where the tag ends.

--- Find all tags starting with the given search term(s).
---
---@param term string|string[] The search term.
---@param opts { search: obsidian.SearchOpts|?, timeout: integer|? }|?
---
---@return obsidian.TagLocation[]
M.find_tags = function(term, opts)
  opts = opts or {}
  return async.block_on(function(cb)
    return M.find_tags_async(term, cb, { search = opts.search })
  end, opts.timeout)
end

--- An async version of 'find_tags()'.
---
---@param term string|string[] The search term.
---@param callback fun(tags: obsidian.TagLocation[])
---@param opts { search: obsidian.SearchOpts|?, dir: obsidian.Path|? }|?
M.find_tags_async = function(term, callback, opts)
  opts = opts or {}

  local Note = require "obsidian.note"

  ---@type string[]
  local terms
  if type(term) == "string" then
    terms = { term }
  else
    terms = term
  end

  for i, t in ipairs(terms) do
    if vim.startswith(t, "#") then
      terms[i] = string.sub(t, 2)
    end
  end

  terms = util.tbl_unique(terms)

  -- Maps paths to tag locations.
  ---@type table<obsidian.Path, obsidian.TagLocation[]>
  local path_to_tag_loc = {}
  -- Caches note objects.
  ---@type table<obsidian.Path, obsidian.Note>
  local path_to_note = {}
  -- Caches code block locations.
  ---@type table<obsidian.Path, { [1]: integer, [2]: integer []}>
  local path_to_code_blocks = {}
  -- Keeps track of the order of the paths.
  ---@type table<string, integer>
  local path_order = {}

  local num_paths = 0
  local err_count = 0
  local first_err = nil
  local first_err_path = nil

  ---@param tag string
  ---@param path string|obsidian.Path
  ---@param note obsidian.Note
  ---@param lnum integer
  ---@param text string
  ---@param col_start integer|?
  ---@param col_end integer|?
  local add_match = function(tag, path, note, lnum, text, col_start, col_end)
    if vim.startswith(tag, "#") then
      tag = string.sub(tag, 2)
    end
    if not path_to_tag_loc[path] then
      path_to_tag_loc[path] = {}
    end
    path_to_tag_loc[path][#path_to_tag_loc[path] + 1] = {
      tag = tag,
      path = path,
      note = note,
      line = lnum,
      text = text,
      tag_start = col_start,
      tag_end = col_end,
    }
  end

  -- Wraps `Note.from_file_with_contents_async()` to return a table instead of a tuple and
  -- find the code blocks.
  ---@param path obsidian.Path
  ---@return { [1]: obsidian.Note, [2]: {[1]: integer, [2]: integer}[] }
  local load_note = function(path)
    local note = Note.from_file(path, {
      load_contents = true,
      max_lines = Obsidian.opts.search.max_lines,
    })
    return { note, M.find_code_blocks(note.contents) }
  end

  ---@param match_data MatchData
  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve { strict = true }

    if path_order[path] == nil then
      num_paths = num_paths + 1
      path_order[path] = num_paths
    end

    -- Load note.
    local note = path_to_note[path]
    local code_blocks = path_to_code_blocks[path]
    if not note or not code_blocks then
      local ok, res = pcall(load_note, path)
      if ok then
        note, code_blocks = unpack(res)
        path_to_note[path] = note
        path_to_code_blocks[path] = code_blocks
      else
        err_count = err_count + 1
        if first_err == nil then
          first_err = res
          first_err_path = path
        end
        return
      end
    end

    -- check if the match was inside a code block.
    for _, block in ipairs(code_blocks) do
      if block[1] <= match_data.line_number and match_data.line_number <= block[2] then
        return
      end
    end

    local line = vim.trim(match_data.lines.text)
    local n_matches = 0

    -- check for tag in the wild of the form '#{tag}'
    for _, match in ipairs(util.parse_tags(line)) do
      local m_start, m_end, _ = unpack(match)
      local tag = string.sub(line, m_start + 1, m_end)
      if string.match(tag, "^" .. M.Patterns.TagCharsRequired .. "$") then
        add_match(tag, path, note, match_data.line_number, line, m_start, m_end)
        n_matches = n_matches + 1
      end
    end

    -- check for tags in frontmatter
    if
      n_matches == 0
      and note.has_frontmatter
      and match_data.line_number < note.frontmatter_end_line
      and note.tags ~= nil
      and (vim.startswith(line, "tags:") or string.match(line, "%s*- "))
    then
      local tag = vim.trim(string.sub(line, 3)) -- HACK: works because we force '  - tag'
      if string.match(tag, "^" .. M.Patterns.TagCharsRequired .. "$") then
        add_match(tag, path, note, match_data.line_number, line)
      end
    end
  end

  local search_terms = {}
  for _, t in ipairs(terms) do
    if string.len(t) > 0 then
      -- tag in the wild
      search_terms[#search_terms + 1] = "#" .. M.Patterns.TagCharsOptional .. t .. M.Patterns.TagCharsOptional
      -- frontmatter tag in multiline list
      search_terms[#search_terms + 1] = "\\s*- "
        .. M.Patterns.TagCharsOptional
        .. t
        .. M.Patterns.TagCharsOptional
        .. "$"
      -- frontmatter tag in inline list
      search_terms[#search_terms + 1] = "tags: .*" .. M.Patterns.TagCharsOptional .. t .. M.Patterns.TagCharsOptional
    else
      -- tag in the wild
      search_terms[#search_terms + 1] = "#" .. M.Patterns.TagCharsRequired
      -- frontmatter tag in multiline list
      search_terms[#search_terms + 1] = "\\s*- " .. M.Patterns.TagCharsRequired .. "$"
      -- frontmatter tag in inline list
      search_terms[#search_terms + 1] = "tags: .*" .. M.Patterns.TagCharsRequired
    end
  end

  M.search_async(
    opts.dir or Obsidian.dir,
    search_terms,
    Opts._prepare(opts.search, { ignore_case = true }),
    on_match,
    function(code)
      if code ~= 0 then
        callback {}
      end
      ---@type obsidian.TagLocation[]
      local tags_list = {}

      -- Order by path.
      local paths = {}
      for path, idx in pairs(path_order) do
        paths[idx] = path
      end

      -- Gather results in path order.
      for _, path in ipairs(paths) do
        local tag_locs = path_to_tag_loc[path]
        if tag_locs ~= nil then
          table.sort(tag_locs, function(a, b)
            return a.line < b.line
          end)
          for _, tag_loc in ipairs(tag_locs) do
            tags_list[#tags_list + 1] = tag_loc
          end
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
