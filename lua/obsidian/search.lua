local Path = require "obsidian.path"
local util = require "obsidian.util"
local log = require "obsidian.log"
local run_job_async = require("obsidian.async").run_job_async
local compat = require "obsidian.compat"
local iter = vim.iter

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
M.find_tags_string = function(s)
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
  run_job_async(cmd, function(line)
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
  run_job_async(cmd, on_match, function(code)
    if on_exit ~= nil then
      on_exit(code)
    end
  end)
end

local default = {
  sort = false,
  include_templates = false,
  ignore_case = false,
}

local function strip_tag(s)
  if vim.startswith(s, "#") then
    return string.sub(s, 2)
  end
  return s
end

---@class obsidian.TagLocation
---
---@field tag string The tag found.
---@field path string The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field tag_start integer|? The index within 'text' where the tag starts.
---@field tag_end integer|? The index within 'text' where the tag ends.

-- TODO: properly ignore_case

---@param query string | table
---@param opts { dir: string, on_match: fun(tag_loc: obsidian.TagLocation) }
---@param callback fun(exit_code: integer, tag_locs: obsidian.TagLocation[])
---@async
M.find_tags = function(query, opts, callback)
  vim.validate("query", query, { "string", "table" })
  vim.validate("callback", callback, "function")
  opts = opts or {}
  opts.dir = opts.dir or require("obsidian").get_client().dir

  -- TODO: read cache

  local terms = type(query) == "string" and { query } or query ---@cast terms -string

  local search_terms = {}
  for _, term in ipairs(terms) do
    if term ~= "" then
      -- Match tags that contain the term
      search_terms[#search_terms + 1] = "\\B#([\\p{L}\\p{N}_-]*" .. term .. "[\\p{L}\\p{N}_-]*)" -- tags in the wild
    else
      -- Match any valid non-empty tag
      search_terms[#search_terms + 1] = "\\B#([\\p{L}\\p{N}_-]+)"
    end
  end

  local results = {}

  M.search_async(opts.dir, search_terms, { ignore_case = true }, function(match)
    local tag_match = match.submatches[1]
    local match_text = tag_match.match.text
    if util.is_hex_color(match_text) then
      return
    end
    ---@type obsidian.TagLocation
    local tag_loc = {
      tag_start = tag_match.start,
      tag_end = tag_match["end"],
      tag = strip_tag(match_text),
      path = match.path.text,
      line = match.line_number,
    }
    table.insert(results, tag_loc)
    if opts.on_match then
      opts.on_match(tag_loc)
    end
  end, function(exit_code)
    callback(exit_code, results)
  end)
end

M.list_tags = function(callback)
  vim.validate("callback", callback, "function")
  local found = {}
  M.find_tags("", {
    on_match = function(tag_loc)
      found[tag_loc.tag] = true
    end,
  }, function()
    callback(vim.tbl_keys(found))
  end)
end

---@param opts obsidian.SearchOpts
---@param additional_opts obsidian.search.SearchOpts|?
---
---@return obsidian.search.SearchOpts
---
---@private
-- local prepare_search_opts = function(opts, additional_opts)
--   local plugin_opts = require("obsidian").get_client().opts
--   opts = vim.tbl_extend("keep", opts, default)
--
--   local search_opts = {}
--
--   if opts.sort then
--     search_opts.sort_by = plugin_opts.sort_by
--     search_opts.sort_reversed = plugin_opts.sort_reversed
--   end
--
--   if not opts.include_templates and plugin_opts.templates ~= nil and plugin_opts.templates.folder ~= nil then
--     M.SearchOpts.add_exclude(search_opts, tostring(plugin_opts.templates.folder))
--   end
--
--   if opts.ignore_case then
--     search_opts.ignore_case = true
--   end
--
--   if additional_opts then
--     search_opts = M.SearchOpts.merge(search_opts, additional_opts)
--   end
--
--   return search_opts
-- end

--  BUG: markdown list item ... just use cache value...

local function build_backlink_search_term(note, anchor, block)
  -- Prepare search terms.
  local search_terms = {}
  local note_path = Path.new(note.path)
  for raw_ref in
    vim.iter {
      tostring(note.id),
      note_path.name,
      note_path.stem,
      -- self:vault_relative_path(note.path), -- TODO:
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

---@class obsidian._BacklinkMatch
---
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.

---@param note obsidian.Note
---@param opts { search: obsidian.SearchOpts, on_match: fun(match: obsidian._BacklinkMatch), anchor: string, block: string }
---@param callback fun(matches: obsidian._BacklinkMatch[])
M.find_backlinks = function(note, opts, callback)
  vim.validate("note", note, "table") -- TODO:
  vim.validate("callback", callback, "function")
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, { dir = tostring(require("obsidian").get_client().dir) })

  local block = opts.block and util.standardize_block(opts.block) or nil
  local anchor = opts.anchor and util.standardize_anchor(opts.anchor) or nil

  local anchor_obj
  if anchor then
    anchor_obj = note:resolve_anchor_link(anchor)
  end

  ---@type obsidian._BacklinkMatch[]
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

---@class obsidian.LinkMatch
---@field link string
---@field line integer

-- TODO: generalize to search link in any note

---@param note obsidian.Note
---@param opts { on_match: fun(link: obsidian.LinkMatch) }
---@param callback fun(links: obsidian.LinkMatch[])
M.find_links = function(note, opts, callback)
  -- Gather all unique raw links (strings) from the buffer.
  ---@type obsidian.LinkMatch[]
  local matches = {}
  ---@type table<string, boolean>
  local found = {}
  local n_lines = vim.api.nvim_buf_line_count(0)
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, true)) do
    for ref_match in vim.iter(M.find_refs(line, { include_naked_urls = true, include_file_urls = true })) do
      local m_start, m_end = unpack(ref_match)
      local link = string.sub(line, m_start, m_end)
      if not found[link] then
        local match = {
          link = link,
          line = lnum,
        }
        matches[#matches + 1] = match
        found[link] = true
        if opts.on_match then
          opts.on_match(match)
        end
      end
    end
    if n_lines == line then
      callback(matches)
    end
  end
end

return M
