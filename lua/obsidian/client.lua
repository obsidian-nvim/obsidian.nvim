--- *obsidian-api*
---
--- The Obsidian.nvim Lua API.
---
--- ==============================================================================
---
--- Table of contents
---
---@toc

local Path = require "obsidian.path"
local async = require "plenary.async"
local channel = require("plenary.async.control").channel
local Note = require "obsidian.note"
local log = require "obsidian.log"
local util = require "obsidian.util"
local search = require "obsidian.search"
local AsyncExecutor = require("obsidian.async").AsyncExecutor
local block_on = require("obsidian.async").block_on
local iter = vim.iter

---@class obsidian.SearchOpts
---
---@field sort boolean|?
---@field include_templates boolean|?
---@field ignore_case boolean|?
---@field default function?

--- The Obsidian client is the main API for programmatically interacting with obsidian.nvim's features
--- in Lua. To get the client instance, run:
---
--- `local client = require("obsidian").get_client()`
---
---@toc_entry obsidian.Client
---
---@class obsidian.Client : obsidian.ABC
local Client = {}

local depreacted_lookup = {
  dir = "dir",
  buf_dir = "buf_dir",
  current_workspace = "workspace",
  opts = "opts",
}

Client.__index = function(_, k)
  if depreacted_lookup[k] then
    local msg = string.format(
      [[client.%s is depreacted, use Obsidian.%s instead.
client is going to be removed in the future as well.]],
      k,
      depreacted_lookup[k]
    )
    log.warn(msg)
    return Obsidian[depreacted_lookup[k]]
  elseif rawget(Client, k) then
    return rawget(Client, k)
  end
end

--- Create a new Obsidian client without additional setup.
--- This is mostly used for testing. In practice you usually want to obtain the existing
--- client through:
---
--- `require("obsidian").get_client()`
---
---@return obsidian.Client
Client.new = function()
  return setmetatable({}, Client)
end

--- Get the default search options.
---
---@return obsidian.SearchOpts
Client.search_defaults = function()
  return {
    sort = false,
    include_templates = false,
    ignore_case = false,
  }
end

---@param opts obsidian.SearchOpts|boolean|?
---
---@return obsidian.SearchOpts
---
---@private
Client._search_opts_from_arg = function(self, opts)
  if opts == nil then
    opts = self:search_defaults()
  elseif type(opts) == "boolean" then
    local sort = opts
    opts = self:search_defaults()
    opts.sort = sort
  end
  return opts
end

---@param opts obsidian.SearchOpts|boolean|?
---@param additional_opts obsidian.search.SearchOpts|?
---
---@return obsidian.search.SearchOpts
---
---@private
Client._prepare_search_opts = function(self, opts, additional_opts)
  opts = self:_search_opts_from_arg(opts)

  local search_opts = {}

  if opts.sort then
    search_opts.sort_by = Obsidian.opts.sort_by
    search_opts.sort_reversed = Obsidian.opts.sort_reversed
  end

  if not opts.include_templates and Obsidian.opts.templates ~= nil and Obsidian.opts.templates.folder ~= nil then
    search.SearchOpts.add_exclude(search_opts, tostring(Obsidian.opts.templates.folder))
  end

  if opts.ignore_case then
    search_opts.ignore_case = true
  end

  if additional_opts ~= nil then
    search_opts = search.SearchOpts.merge(search_opts, additional_opts)
  end

  return search_opts
end

---@param term string
---@param search_opts obsidian.SearchOpts|boolean|?
---@param find_opts obsidian.SearchOpts|boolean|?
---
---@return function
---
---@private
Client._search_iter_async = function(self, term, search_opts, find_opts)
  local tx, rx = channel.mpsc()
  local found = {}

  local function on_exit(_)
    tx.send(nil)
  end

  ---@param content_match MatchData
  local function on_search_match(content_match)
    local path = Path.new(content_match.path.text):resolve { strict = true }
    if not found[path.filename] then
      found[path.filename] = true
      tx.send(path)
    end
  end

  ---@param path_match string
  local function on_find_match(path_match)
    local path = Path.new(path_match):resolve { strict = true }
    if not found[path.filename] then
      found[path.filename] = true
      tx.send(path)
    end
  end

  local cmds_done = 0 -- out of the two, one for 'search' and one for 'find'

  search.search_async(
    Obsidian.dir,
    term,
    self:_prepare_search_opts(search_opts, { fixed_strings = true, max_count_per_file = 1 }),
    on_search_match,
    on_exit
  )

  search.find_async(
    Obsidian.dir,
    term,
    self:_prepare_search_opts(find_opts, { ignore_case = true }),
    on_find_match,
    on_exit
  )

  return function()
    while cmds_done < 2 do
      local value = rx.recv()
      if value == nil then
        cmds_done = cmds_done + 1
      else
        return value
      end
    end
    return nil
  end
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
Client.find_tags = function(self, term, opts)
  opts = opts or {}
  return block_on(function(cb)
    return self:find_tags_async(term, cb, { search = opts.search })
  end, opts.timeout)
end

--- An async version of 'find_tags()'.
---
---@param term string|string[] The search term.
---@param callback fun(tags: obsidian.TagLocation[])
---@param opts { search: obsidian.SearchOpts }|?
Client.find_tags_async = function(self, term, callback, opts)
  opts = opts or {}

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

  local executor = AsyncExecutor.new()

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
    local note, contents = Note.from_file_with_contents_async(path, { max_lines = Obsidian.opts.search_max_lines })
    return { note, search.find_code_blocks(contents) }
  end

  ---@param match_data MatchData
  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve { strict = true }

    if path_order[path] == nil then
      num_paths = num_paths + 1
      path_order[path] = num_paths
    end

    executor:submit(function()
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

      local line_number = match_data.line_number + 1 -- match_data.line_number is 0-indexed

      -- check if the match was inside a code block.
      for block in iter(code_blocks) do
        if block[1] <= line_number and line_number <= block[2] then
          return
        end
      end

      local line = vim.trim(match_data.lines.text)
      local n_matches = 0

      -- check for tag in the wild of the form '#{tag}'
      for match in iter(search.find_tags(line)) do
        local m_start, m_end, _ = unpack(match)
        local tag = string.sub(line, m_start + 1, m_end)
        if string.match(tag, "^" .. search.Patterns.TagCharsRequired .. "$") then
          add_match(tag, path, note, match_data.line_number, line, m_start, m_end)
        end
      end

      -- check for tags in frontmatter
      if n_matches == 0 and note.tags ~= nil and (vim.startswith(line, "tags:") or string.match(line, "%s*- ")) then
        for tag in iter(note.tags) do
          tag = tostring(tag)
          for _, t in ipairs(terms) do
            if string.len(t) == 0 or util.string_contains(tag:lower(), t:lower()) then
              add_match(tag, path, note, match_data.line_number, line)
            end
          end
        end
      end
    end)
  end

  local tx, rx = channel.oneshot()

  local search_terms = {}
  for t in iter(terms) do
    if string.len(t) > 0 then
      -- tag in the wild
      search_terms[#search_terms + 1] = "#" .. search.Patterns.TagCharsOptional .. t .. search.Patterns.TagCharsOptional
      -- frontmatter tag in multiline list
      search_terms[#search_terms + 1] = "\\s*- "
        .. search.Patterns.TagCharsOptional
        .. t
        .. search.Patterns.TagCharsOptional
        .. "$"
      -- frontmatter tag in inline list
      search_terms[#search_terms + 1] = "tags: .*"
        .. search.Patterns.TagCharsOptional
        .. t
        .. search.Patterns.TagCharsOptional
    else
      -- tag in the wild
      search_terms[#search_terms + 1] = "#" .. search.Patterns.TagCharsRequired
      -- frontmatter tag in multiline list
      search_terms[#search_terms + 1] = "\\s*- " .. search.Patterns.TagCharsRequired .. "$"
      -- frontmatter tag in inline list
      search_terms[#search_terms + 1] = "tags: .*" .. search.Patterns.TagCharsRequired
    end
  end

  search.search_async(
    Obsidian.dir,
    search_terms,
    self:_prepare_search_opts(opts.search, { ignore_case = true }),
    on_match,
    function(_)
      tx()
    end
  )

  async.run(function()
    rx()
    executor:join_async()

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

    return tags_list
  end, callback)
end

---@class obsidian.BacklinkMatches
---
---@field note obsidian.Note The note instance where the backlinks were found.
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field matches obsidian.BacklinkMatch[] The backlinks within the note.

---@class obsidian.BacklinkMatch
---
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.

--- Find all backlinks to a note.
---
---@param note obsidian.Note The note to find backlinks for.
---@param opts { search: obsidian.SearchOpts|?, timeout: integer|?, anchor: string|?, block: string|? }|?
---
---@return obsidian.BacklinkMatches[]
Client.find_backlinks = function(self, note, opts)
  opts = opts or {}
  return block_on(function(cb)
    return self:find_backlinks_async(note, cb, { search = opts.search, anchor = opts.anchor, block = opts.block })
  end, opts.timeout)
end

--- An async version of 'find_backlinks()'.
---
---@param note obsidian.Note The note to find backlinks for.
---@param callback fun(backlinks: obsidian.BacklinkMatches[])
---@param opts { search: obsidian.SearchOpts, anchor: string|?, block: string|? }|?
Client.find_backlinks_async = function(self, note, callback, opts)
  opts = opts or {}

  ---@type string|?
  local block = opts.block and util.standardize_block(opts.block) or nil
  local anchor = opts.anchor and util.standardize_anchor(opts.anchor) or nil
  ---@type obsidian.note.HeaderAnchor|?
  local anchor_obj
  if anchor then
    anchor_obj = note:resolve_anchor_link(anchor)
  end

  -- Maps paths (string) to note object and a list of matches.
  ---@type table<string, obsidian.BacklinkMatch[]>
  local backlink_matches = {}
  ---@type table<string, obsidian.Note>
  local path_to_note = {}
  -- Keeps track of the order of the paths.
  ---@type table<string, integer>
  local path_order = {}
  local num_paths = 0
  local err_count = 0
  local first_err = nil
  local first_err_path = nil

  local executor = AsyncExecutor.new()

  -- Prepare search terms.
  local search_terms = {}
  local note_path = Path.new(note.path)
  for raw_ref in iter { tostring(note.id), note_path.name, note_path.stem, note.path:vault_relative_path() } do
    for ref in
      iter(util.tbl_unique {
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
  for alias in iter(note.aliases) do
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

  ---@type obsidian.note.LoadOpts
  local load_opts = {
    collect_anchor_links = opts.anchor ~= nil,
    collect_blocks = opts.block ~= nil,
    max_lines = Obsidian.opts.search_max_lines,
  }

  ---@param match MatchData
  local function on_match(match)
    local path = Path.new(match.path.text):resolve { strict = true }

    if path_order[path] == nil then
      num_paths = num_paths + 1
      path_order[path] = num_paths
    end

    executor:submit(function()
      -- Load note.
      local n = path_to_note[path]
      if not n then
        local ok, res = pcall(Note.from_file_async, path, load_opts)
        if ok then
          n = res
          path_to_note[path] = n
        else
          err_count = err_count + 1
          if first_err == nil then
            first_err = res
            first_err_path = path
          end
          return
        end
      end

      if anchor then
        -- Check for a match with the anchor.
        -- NOTE: no need to do this with blocks, since blocks are standardized.
        local match_text = string.sub(match.lines.text, match.submatches[1].start)
        local link_location = util.parse_link(match_text)
        if not link_location then
          log.error("Failed to parse reference from '%s' ('%s')", match_text, match)
          return
        end

        local anchor_link = select(2, util.strip_anchor_links(link_location))
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

      ---@type obsidian.BacklinkMatch[]
      local line_matches = backlink_matches[path]
      if line_matches == nil then
        line_matches = {}
        backlink_matches[path] = line_matches
      end

      line_matches[#line_matches + 1] = {
        line = match.line_number,
        text = util.rstrip_whitespace(match.lines.text),
      }
    end)
  end

  local tx, rx = channel.oneshot()

  -- Execute search.
  search.search_async(
    Obsidian.dir,
    util.tbl_unique(search_terms),
    self:_prepare_search_opts(opts.search, { fixed_strings = true, ignore_case = true }),
    on_match,
    function()
      tx()
    end
  )

  async.run(function()
    rx()
    executor:join_async()

    ---@type obsidian.BacklinkMatches[]
    local results = {}

    -- Order by path.
    local paths = {}
    for path, idx in pairs(path_order) do
      paths[idx] = path
    end

    -- Gather results.
    for i, path in ipairs(paths) do
      results[i] = { note = path_to_note[path], path = path, matches = backlink_matches[path] }
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

    return vim.tbl_filter(function(bl)
      return bl.matches ~= nil
    end, results)
  end, callback)
end

--- Gather a list of all tags in the vault. If 'term' is provided, only tags that partially match the search
--- term will be included.
---
---@param term string|? An optional search term to match tags
---@param timeout integer|? Timeout in milliseconds
---
---@return string[]
Client.list_tags = function(self, term, timeout)
  local tags = {}
  for _, tag_loc in ipairs(self:find_tags(term and term or "", { timeout = timeout })) do
    tags[tag_loc.tag] = true
  end
  return vim.tbl_keys(tags)
end

--- An async version of 'list_tags()'.
---
---@param term string|?
---@param callback fun(tags: string[])
Client.list_tags_async = function(self, term, callback)
  self:find_tags_async(term and term or "", function(tag_locations)
    local tags = {}
    for _, tag_loc in ipairs(tag_locations) do
      local tag = tag_loc.tag:lower()
      if not tags[tag] then
        tags[tag] = true
      end
    end
    callback(vim.tbl_keys(tags))
  end)
end

return Client
