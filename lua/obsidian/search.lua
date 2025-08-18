local Path = require "obsidian.path"
local util = require "obsidian.util"
local iter = vim.iter
local compat = require "obsidian.compat"
local log = require "obsidian.log"
local async = require "obsidian.async"

local M = {}

M._BASE_CMD = { "rg", "--no-config", "--type=md" }
M._SEARCH_CMD = compat.flatten { M._BASE_CMD, "--json" }
M._FIND_CMD = compat.flatten { M._BASE_CMD, "--files" }

---@enum obsidian.search.RefTypes
M.RefTypes = {
  WikiWithAlias = "WikiWithAlias",
  Wiki = "Wiki",
  Markdown = "Markdown",
  NakedUrl = "NakedUrl",
  FileUrl = "FileUrl",
  MailtoUrl = "MailtoUrl",
  Tag = "Tag",
  BlockID = "BlockID",
  Highlight = "Highlight",
}

---@enum obsidian.search.Patterns
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
  NakedUrl = "https?://[a-zA-Z0-9._-@]+[a-zA-Z0-9._#/=&?:+%%-@]+[a-zA-Z0-9/]", -- https://xyz.com
  FileUrl = "file:/[/{2}]?.*", -- file:///
  MailtoUrl = "mailto:.*", -- mailto:emailaddress
  BlockID = util.BLOCK_PATTERN .. "$", -- ^hello-world
}

---@type table<obsidian.search.RefTypes, { ignore_if_escape_prefix: boolean|? }>
M.PatternConfig = {
  [M.RefTypes.Tag] = { ignore_if_escape_prefix = true },
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
  for pattern_name in iter(pattern_names) do
    local pattern = M.Patterns[pattern_name]
    local pattern_cfg = M.PatternConfig[pattern_name]
    local search_start = 1
    while search_start < #s do
      local m_start, m_end = string.find(s, pattern, search_start)
      if m_start ~= nil and m_end ~= nil then
        -- Check if we're inside a code block.
        local inside_code_block = false
        for code_block_boundary in iter(inline_code_blocks) do
          if code_block_boundary[1] < m_start and m_end < code_block_boundary[2] then
            inside_code_block = true
            break
          end
        end

        if not inside_code_block then
          -- Check if this match overlaps with any others (e.g. a naked URL match would be contained in
          -- a markdown URL).
          local overlap = false
          for match in iter(matches) do
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
  for match in iter(M.find_matches(s, { M.RefTypes.Highlight })) do
    -- Remove highlights that begin/end with whitespace
    local match_start, match_end, _ = unpack(match)
    local text = string.sub(s, match_start + 2, match_end - 2)
    if vim.trim(text) == text then
      matches[#matches + 1] = match
    end
  end
  return matches
end

---@class obsidian.search.FindRefsOpts
---
---@field include_naked_urls boolean|?
---@field include_tags boolean|?
---@field include_file_urls boolean|?
---@field include_block_ids boolean|?

--- Find refs and URLs.
---@param s string the string to search
---@param opts obsidian.search.FindRefsOpts|?
---
---@return { [1]: integer, [2]: integer, [3]: obsidian.search.RefTypes }[]
M.find_refs = function(s, opts)
  opts = opts and opts or {}

  local pattern_names = { M.RefTypes.WikiWithAlias, M.RefTypes.Wiki, M.RefTypes.Markdown }
  if opts.include_naked_urls then
    pattern_names[#pattern_names + 1] = M.RefTypes.NakedUrl
  end
  if opts.include_tags then
    pattern_names[#pattern_names + 1] = M.RefTypes.Tag
  end
  if opts.include_file_urls then
    pattern_names[#pattern_names + 1] = M.RefTypes.FileUrl
  end
  if opts.include_block_ids then
    pattern_names[#pattern_names + 1] = M.RefTypes.BlockID
  end

  return M.find_matches(s, pattern_names)
end

--- Find all tags in a string.
---@param s string the string to search
---
---@return {[1]: integer, [2]: integer, [3]: obsidian.search.RefTypes}[]
M.find_tags = function(s)
  local matches = {}
  for match in iter(M.find_matches(s, { M.RefTypes.Tag })) do
    local st, ed, m_type = unpack(match)
    local match_string = s:sub(st, ed)
    if m_type == M.RefTypes.Tag and not util.is_hex_color(match_string) then
      matches[#matches + 1] = match
    end
  end
  return matches
end

--- Replace references of the form '[[xxx|xxx]]', '[[xxx]]', or '[xxx](xxx)' with their title.
---
---@param s string
---
---@return string
M.replace_refs = function(s)
  local out, _ = string.gsub(s, "%[%[[^%|%]]+%|([^%]]+)%]%]", "%1")
  out, _ = out:gsub("%[%[([^%]]+)%]%]", "%1")
  out, _ = out:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
  return out
end

--- Find all refs in a string and replace with their titles.
---
---@param s string
--
---@return string
---@return table
---@return string[]
M.find_and_replace_refs = function(s)
  local pieces = {}
  local refs = {}
  local is_ref = {}
  local matches = M.find_refs(s)
  local last_end = 1
  for _, match in pairs(matches) do
    local m_start, m_end, _ = unpack(match)
    assert(type(m_start) == "number")
    if last_end < m_start then
      table.insert(pieces, string.sub(s, last_end, m_start - 1))
      table.insert(is_ref, false)
    end
    local ref_str = string.sub(s, m_start, m_end)
    table.insert(pieces, M.replace_refs(ref_str))
    table.insert(refs, ref_str)
    table.insert(is_ref, true)
    last_end = m_end + 1
  end

  local indices = {}
  local length = 0
  for i, piece in ipairs(pieces) do
    local i_end = length + string.len(piece)
    if is_ref[i] then
      table.insert(indices, { length + 1, i_end })
    end
    length = i_end
  end

  return table.concat(pieces, ""), indices, refs
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

---@class obsidian.search.SearchOpts
---
---@field sort_by obsidian.config.SortBy|?
---@field sort_reversed boolean|?
---@field fixed_strings boolean|?
---@field ignore_case boolean|?
---@field smart_case boolean|?
---@field exclude string[]|? paths to exclude
---@field max_count_per_file integer|?
---@field escape_path boolean|?
---@field include_non_markdown boolean|?

local SearchOpts = {}
M.SearchOpts = SearchOpts

SearchOpts.as_tbl = function(self)
  local fields = {}
  for k, v in pairs(self) do
    if not vim.startswith(k, "__") then
      fields[k] = v
    end
  end
  return fields
end

---@param one obsidian.search.SearchOpts|table
---@param other obsidian.search.SearchOpts|table
---@return obsidian.search.SearchOpts
SearchOpts.merge = function(one, other)
  return vim.tbl_extend("force", SearchOpts.as_tbl(one), SearchOpts.as_tbl(other))
end

---@param opts obsidian.search.SearchOpts
---@param path string
SearchOpts.add_exclude = function(opts, path)
  if opts.exclude == nil then
    opts.exclude = {}
  end
  opts.exclude[#opts.exclude + 1] = path
end

---@param opts obsidian.search.SearchOpts
---@return string[]
SearchOpts.to_ripgrep_opts = function(opts)
  local ret = {}

  if opts.sort_by ~= nil then
    local sort = "sortr" -- default sort is reverse
    if opts.sort_reversed == false then
      sort = "sort"
    end
    ret[#ret + 1] = "--" .. sort .. "=" .. opts.sort_by
  end

  if opts.fixed_strings then
    ret[#ret + 1] = "--fixed-strings"
  end

  if opts.ignore_case then
    ret[#ret + 1] = "--ignore-case"
  end

  if opts.smart_case then
    ret[#ret + 1] = "--smart-case"
  end

  if opts.exclude ~= nil then
    assert(type(opts.exclude) == "table")
    for path in iter(opts.exclude) do
      ret[#ret + 1] = "-g!" .. path
    end
  end

  if opts.max_count_per_file ~= nil then
    ret[#ret + 1] = "-m=" .. opts.max_count_per_file
  end

  return ret
end

---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_search_cmd = function(dir, term, opts)
  opts = opts and opts or {}

  local search_terms
  if type(term) == "string" then
    search_terms = { "-e", term }
  else
    search_terms = {}
    for t in iter(term) do
      search_terms[#search_terms + 1] = "-e"
      search_terms[#search_terms + 1] = t
    end
  end

  local path = tostring(Path.new(dir):resolve { strict = true })
  if opts.escape_path then
    path = assert(vim.fn.fnameescape(path))
  end

  return compat.flatten {
    M._SEARCH_CMD,
    SearchOpts.to_ripgrep_opts(opts),
    search_terms,
    path,
  }
end

--- Build the 'rg' command for finding files.
---
---@param path string|?
---@param term string|?
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_find_cmd = function(path, term, opts)
  opts = opts and opts or {}

  local additional_opts = {}

  if term ~= nil then
    if opts.include_non_markdown then
      term = "*" .. term .. "*"
    elseif not vim.endswith(term, ".md") then
      term = "*" .. term .. "*.md"
    else
      term = "*" .. term
    end
    additional_opts[#additional_opts + 1] = "-g"
    additional_opts[#additional_opts + 1] = term
  end

  if opts.ignore_case then
    additional_opts[#additional_opts + 1] = "--glob-case-insensitive"
  end

  if path ~= nil and path ~= "." then
    if opts.escape_path then
      path = assert(vim.fn.fnameescape(tostring(path)))
    end
    additional_opts[#additional_opts + 1] = path
  end

  return compat.flatten { M._FIND_CMD, SearchOpts.to_ripgrep_opts(opts), additional_opts }
end

--- Build the 'rg' grep command for pickers.
---
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_grep_cmd = function(opts)
  opts = opts and opts or {}

  return compat.flatten {
    M._BASE_CMD,
    SearchOpts.to_ripgrep_opts(opts),
    "--column",
    "--line-number",
    "--no-heading",
    "--with-filename",
    "--color=never",
  }
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

local search_defualts = {
  sort = false,
  include_templates = false,
  ignore_case = false,
}

---@param opts obsidian.SearchOpts|boolean|?
---@param additional_opts obsidian.search.SearchOpts|?
---
---@return obsidian.search.SearchOpts
---
---@private
local _prepare_search_opts = function(opts, additional_opts)
  opts = opts or search_defualts

  local search_opts = {}

  if opts.sort then
    search_opts.sort_by = Obsidian.opts.sort_by
    search_opts.sort_reversed = Obsidian.opts.sort_reversed
  end

  if not opts.include_templates and Obsidian.opts.templates ~= nil and Obsidian.opts.templates.folder ~= nil then
    M.SearchOpts.add_exclude(search_opts, tostring(Obsidian.opts.templates.folder))
  end

  if opts.ignore_case then
    search_opts.ignore_case = true
  end

  if additional_opts ~= nil then
    search_opts = M.SearchOpts.merge(search_opts, additional_opts)
  end

  return search_opts
end

---@param term string
---@param search_opts obsidian.SearchOpts|boolean|?
---@param find_opts obsidian.SearchOpts|boolean|?
---@param callback fun(path: obsidian.Path)
---@param exit_callback fun(paths: obsidian.Path[])
local _search_async = function(term, search_opts, find_opts, callback, exit_callback)
  local found = {}
  local result = {}
  local cmds_done = 0

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
    Obsidian.dir,
    term,
    _prepare_search_opts(search_opts, { fixed_strings = true, max_count_per_file = 1 }),
    on_search_match,
    on_exit
  )

  M.find_async(Obsidian.dir, term, _prepare_search_opts(find_opts, { ignore_case = true }), on_find_match, on_exit)
end

--- An async version of `find_notes()` using coroutines.
---
---@param term string The term to search for
---@param callback fun(notes: obsidian.Note[])
---@param opts { search: obsidian.SearchOpts|?, notes: obsidian.note.LoadOpts|? }|?
M.find_notes_async = function(term, callback, opts)
  async.run(function()
    opts = opts or {}
    opts.notes = opts.notes or {}
    if not opts.notes.max_lines then
      opts.notes.max_lines = Obsidian.opts.search_max_lines
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
    async.await(5, _search_async, term, opts.search, nil, function(path)
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
    if first_err and first_err_path then
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
---@param callback fun(results: obsidian.Note[])
---@param opts { notes: obsidian.note.LoadOpts|? }|?
---
---@return obsidian.Note|?
local _resolve_note_async = function(query, callback, opts)
  opts = opts or {}
  opts.notes = opts.notes or {}
  if not opts.notes.max_lines then
    opts.notes.max_lines = Obsidian.opts.search_max_lines
  end
  local Note = require "obsidian.note"

  -- Autocompletion for command args will have this format.
  local note_path, count = string.gsub(query, "^.*  ", "")
  if count > 0 then
    ---@type obsidian.Path
    ---@diagnostic disable-next-line: assign-type-mismatch
    local full_path = Obsidian.dir / note_path
    callback { Note.from_file(full_path, opts.notes) }
  end

  -- Query might be a path.
  local fname = query
  if not vim.endswith(fname, ".md") then
    fname = fname .. ".md"
  end

  local paths_to_check = { Path.new(fname), Obsidian.dir / fname }

  if Obsidian.opts.notes_subdir ~= nil then
    paths_to_check[#paths_to_check + 1] = Obsidian.dir / Obsidian.opts.notes_subdir / fname
  end

  if Obsidian.opts.daily_notes.folder ~= nil then
    paths_to_check[#paths_to_check + 1] = Obsidian.dir / Obsidian.opts.daily_notes.folder / fname
  end

  if Obsidian.buf_dir ~= nil then
    paths_to_check[#paths_to_check + 1] = Obsidian.buf_dir / fname
  end

  for _, path in pairs(paths_to_check) do
    if path:is_file() then
      return callback { Note.from_file(path, opts.notes) }
    end
  end

  M.find_notes_async(query, function(results)
    local query_lwr = string.lower(query)

    -- We'll gather both exact matches (of ID, filename, and aliases) and fuzzy matches.
    -- If we end up with any exact matches, we'll return those. Otherwise we fall back to fuzzy
    -- matches.
    ---@type obsidian.Note[]
    local exact_matches = {}
    ---@type obsidian.Note[]
    local fuzzy_matches = {}

    for note in iter(results) do
      ---@cast note obsidian.Note

      local reference_ids = note:reference_ids { lowercase = true }

      -- Check for exact match.
      if vim.list_contains(reference_ids, query_lwr) then
        table.insert(exact_matches, note)
      else
        -- Fall back to fuzzy match.
        for ref_id in iter(reference_ids) do
          if util.string_contains(ref_id, query_lwr) then
            table.insert(fuzzy_matches, note)
            break
          end
        end
      end
    end

    if #exact_matches > 0 then
      return callback(exact_matches)
    else
      return callback(fuzzy_matches)
    end
  end, { search = { sort = true, ignore_case = true }, notes = opts.notes })
end

--- Resolve a note, opens a picker to choose a single note when there are multiple matches.
---
---@param query string
---@param callback fun(note: obsidian.Note|nil)
---@param opts { notes: obsidian.note.LoadOpts|?, prompt_title: string|?, pick: boolean }|?
---
---@return obsidian.Note|?
M.resolve_note_async = function(query, callback, opts)
  opts = opts or {}
  opts.pick = vim.F.if_nil(opts.pick, true)

  _resolve_note_async(query, function(notes)
    if #notes == 0 then
      return callback()
    elseif #notes == 1 then
      return callback(notes[1])
    end
    if opts.pick then
      -- Fall back to picker.
      vim.schedule(function()
        -- Otherwise run the preferred picker to search for notes.
        local picker = Obsidian.picker
        if not picker then
          return log.err("Found multiple notes matching '%s', but no picker is configured", query)
        end

        picker:pick_note(notes, {
          prompt_title = opts.prompt_title,
          callback = callback,
        })
      end)
    else
      return log.err("Failed to resolve '%s' to a single note, found %d matches", query, #notes)
    end
  end, { notes = opts.notes })
end

---@param term string
---@param opts? table
---@return obsidian.Note
M.resolve_note = function(term, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  return async.block_on(function(cb)
    return M.resolve_note_async(term, cb, { search = opts.search })
  end, opts.timeout)
end

---@class obsidian.ResolveLinkResult
---
---@field location string
---@field name string
---@field link_type obsidian.search.RefTypes
---@field path obsidian.Path|?
---@field note obsidian.Note|?
---@field url string|?
---@field line integer|?
---@field col integer|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?

--- Resolve a link.
---
---@param link string
---@param callback fun(results: obsidian.ResolveLinkResult?)
---@param opts? { pick: boolean }
M.resolve_link_async = function(link, callback, opts)
  opts = opts or { pick = false }
  local Note = require "obsidian.note"

  local location, name, link_type
  location, name, link_type = util.parse_link(link, { include_naked_urls = true, include_file_urls = true })

  if location == nil or name == nil or link_type == nil then
    return callback()
  end

  ---@type obsidian.ResolveLinkResult
  local res = { location = location, name = name, link_type = link_type }

  if util.is_url(location) then
    res.url = location
    return callback(res)
  end

  -- The Obsidian app will follow URL-encoded links, so we should to.
  location = vim.uri_decode(location)

  -- Remove block links from the end if there are any.
  -- TODO: handle block links.
  ---@type string|?
  local block_link
  location, block_link = util.strip_block_links(location)

  -- Remove anchor links from the end if there are any.
  ---@type string|?
  local anchor_link
  location, anchor_link = util.strip_anchor_links(location)

  --- Finalize the `obsidian.ResolveLinkResult` for a note while resolving block or anchor link to line.
  ---
  ---@param note obsidian.Note|nil
  ---@return obsidian.ResolveLinkResult?
  local function finalize_result(note)
    if not note then
      return log.err "No note found"
    end

    ---@type integer|?, obsidian.note.Block|?, obsidian.note.HeaderAnchor|?
    local line, block_match, anchor_match
    if block_link ~= nil then
      block_match = note:resolve_block(block_link)
      if block_match then
        line = block_match.line
      end
    elseif anchor_link ~= nil then
      anchor_match = note:resolve_anchor_link(anchor_link)
      if anchor_match then
        line = anchor_match.line
      end
    end

    return vim.tbl_extend(
      "force",
      res,
      { path = note.path, note = note, line = line, block = block_match, anchor = anchor_match }
    )
  end

  ---@type obsidian.note.LoadOpts
  local load_opts = {
    collect_anchor_links = anchor_link and true or false,
    collect_blocks = block_link and true or false,
    max_lines = Obsidian.opts.search_max_lines,
  }

  -- Assume 'location' is current buffer path if empty, like for TOCs.
  if string.len(location) == 0 then
    res.location = vim.api.nvim_buf_get_name(0)
    local note = Note.from_buffer(0, load_opts)
    return callback(finalize_result(note))
  end

  res.location = location

  M.resolve_note_async(location, function(note)
    if not note then
      local path = Path.new(location)
      if path:exists() then
        res.path = path
        return callback(res)
      else
        return callback(res)
      end
    end

    return callback(finalize_result(note))
  end, { notes = load_opts, pick = opts.pick })
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
    for ref_match in vim.iter(M.find_refs(line, { include_naked_urls = true, include_file_urls = true })) do
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
  local note_path = Path.new(note.path)
  for raw_ref in
    vim.iter {
      tostring(note.id),
      note_path.name,
      note_path.stem,
      note.path:vault_relative_path(),
    }

  do
    for ref in
      vim.iter(util.tbl_unique {
        raw_ref,
        util.urlencode(tostring(raw_ref)),
        util.urlencode(tostring(raw_ref), { keep_path_sep = true }),
      })

    do
      if ref ~= nil then
        if anchor == nil and block == nil then
          -- Wiki links without anchor/block.
          search_terms[#search_terms + 1] = string.format("[[%s]]", ref)
          search_terms[#search_terms + 1] = string.format("[[%s|", ref)
          -- Markdown link without anchor/block.
          search_terms[#search_terms + 1] = string.format("(%s)", ref)
          -- Markdown link without anchor/block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s)", ref)
          -- Wiki links with anchor/block.
          search_terms[#search_terms + 1] = string.format("[[%s#", ref)
          -- Markdown link with anchor/block.
          search_terms[#search_terms + 1] = string.format("(%s#", ref)
          -- Markdown link with anchor/block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#", ref)
        elseif anchor then
          -- Note: Obsidian allow a lot of different forms of anchor links, so we can't assume
          -- it's the standardized form here.
          -- Wiki links with anchor.
          search_terms[#search_terms + 1] = string.format("[[%s#", ref)
          -- Markdown link with anchor.
          search_terms[#search_terms + 1] = string.format("(%s#", ref)
          -- Markdown link with anchor and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#", ref)
        elseif block then
          -- Wiki links with block.
          search_terms[#search_terms + 1] = string.format("[[%s#%s", ref, block)
          -- Markdown link with block.
          search_terms[#search_terms + 1] = string.format("(%s#%s", ref, block)
          -- Markdown link with block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#%s", ref, block)
        end
      end
    end
  end
  for alias in vim.iter(note.aliases) do
    if anchor == nil and block == nil then
      -- Wiki link without anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s]]", alias)
      -- Wiki link with anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif anchor then
      -- Wiki link with anchor.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif block then
      -- Wiki link with block.
      search_terms[#search_terms + 1] = string.format("[[%s#%s", alias, block)
    end
  end
  return search_terms
end

---@class obsidian.BacklinkMatch
---
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.
---@field start integer The start of match (0-indexed)
---@field end integer The end of match (0-indexed)

---@param note obsidian.Note
---@param callback fun(matches: obsidian.BacklinkMatch[])
---@param opts { search: obsidian.SearchOpts, on_match: fun(match: obsidian.BacklinkMatch), anchor: string, block: string }
M.find_backlinks_async = function(note, callback, opts)
  vim.validate("note", note, "table")
  vim.validate("callback", callback, "function")
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, { dir = Obsidian.dir })
  local block = opts.block and util.standardize_block(opts.block) or nil
  local anchor = opts.anchor and util.standardize_anchor(opts.anchor) or nil
  local anchor_obj
  if anchor then
    anchor_obj = note:resolve_anchor_link(anchor)
  end
  ---@type obsidian.BacklinkMatch[]
  local results = {}
  ---@param match MatchData
  local _on_match = function(match)
    local path = Path.new(match.path.text):resolve { strict = true }
    if anchor then
      -- Check for a match with the anchor.
      -- NOTE: no need to do this with blocks, since blocks are standardized.
      local match_text = string.sub(match.lines.text, match.submatches[1].start)
      local link_location = util.parse_link(match_text)
      if not link_location then
        log.error("Failed to parse reference from '%s' ('%s')", match_text, match)
        return
      end
      local anchor_link = select(2, vim.trim(link_location))
      if not anchor_link then
        return
      end
      if anchor_link ~= anchor and anchor_obj ~= nil then
        local resolved_anchor = note:resolve_anchor_link(anchor_link)
        if resolved_anchor == nil or resolved_anchor.header ~= anchor_obj.header then
          return
        end
      end
    end
    results[#results + 1] = {
      path = path,
      line = match.line_number,
      text = util.rstrip_whitespace(match.lines.text),
      start = match.submatches[1].start,
      ["end"] = match.submatches[1]["end"],
    }
  end
  M.search_async(
    opts.dir,
    build_backlink_search_term(note, anchor, block),
    { fixed_strings = true, ignore_case = true },
    _on_match,
    function()
      callback(results)
    end
  )
end

---@param note obsidian.Note
---@param opts { search: obsidian.SearchOpts, anchor: string, block: string, timeout: integer }?
---@return obsidian.BacklinkMatch
M.find_backlinks = function(note, opts)
  opts = opts or {}
  opts.timeout = opts.timeout or 1000
  return async.block_on(function(cb)
    return M.find_backlinks_async(note, cb, { search = opts.search, anchor = opts.anchor, block = opts.block })
  end, opts.timeout)
end

return M
