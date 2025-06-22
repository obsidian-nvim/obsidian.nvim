local search = require "obsidian.search"
local util = require "obsidian.util"
local Path = require "obsidian.path"
local log = require "obsidian.log"

local function strip_tag(s)
  if vim.startswith(s, "#") then
    return string.sub(s, 2)
  elseif vim.startswith(s, "  - ") then
    return string.sub(s, 5)
  end
  return s
end

local default = {
  sort = false,
  include_templates = false,
  ignore_case = false,
}

---@param opts obsidian.SearchOpts
---@param additional_opts obsidian.search.SearchOpts|?
---
---@return obsidian.search.SearchOpts
---
---@private
local prepare_search_opts = function(opts, additional_opts)
  local plugin_opts = require("obsidian").get_client().opts
  opts = vim.tbl_extend("keep", opts, default)

  local search_opts = {}

  if opts.sort then
    search_opts.sort_by = plugin_opts.sort_by
    search_opts.sort_reversed = plugin_opts.sort_reversed
  end

  if not opts.include_templates and plugin_opts.templates ~= nil and plugin_opts.templates.folder ~= nil then
    search.SearchOpts.add_exclude(search_opts, tostring(plugin_opts.templates.folder))
  end

  if opts.ignore_case then
    search_opts.ignore_case = true
  end

  if additional_opts then
    search_opts = search.SearchOpts.merge(search_opts, additional_opts)
  end

  return search_opts
end

---@class obsidian._TagLocation
---
---@field tag string The tag found.
---@field path string The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field tag_start integer|? The index within 'text' where the tag starts.
---@field tag_end integer|? The index within 'text' where the tag ends.

-- TODO: query properly ignore_case, music and Music is same tag

---@param query string | table
---@param opts { dir: string, on_match: fun(tag_loc: obsidian._TagLocation) }
---@param on_finish fun(tag_locs: obsidian._TagLocation[])
---@async
local function find_tags(query, opts, on_finish)
  vim.validate("query", query, { "string", "table" })
  vim.validate("on_finish", on_finish, "function")
  opts = opts or {}
  opts.dir = opts.dir or require("obsidian").get_client().dir

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

  search.search_async(opts.dir, search_terms, { ignore_case = true }, function(match)
    local tag_match = match.submatches[1]
    local match_text = tag_match.match.text

    if util.is_hex_color(match_text) then
      return
    end

    ---@type obsidian._TagLocation
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
    on_finish(results)
  end)
end

local function list_tags(callback)
  vim.validate("callback", callback, "function")
  local found = {}
  find_tags("", {
    on_match = function(tag_loc)
      found[tag_loc.tag] = true
    end,
  }, function(tag_locs)
    callback(vim.tbl_keys(found))
  end)
end

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
local function find_backlinks(note, opts, callback)
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

  search.search_async(
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
local function find_links(note, opts, callback)
  -- Gather all unique raw links (strings) from the buffer.
  ---@type obsidian.LinkMatch[]
  local matches = {}
  ---@type table<string, boolean>
  local found = {}
  local n_lines = vim.api.nvim_buf_line_count(0)
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, true)) do
    for ref_match in vim.iter(search.find_refs(line, { include_naked_urls = true, include_file_urls = true })) do
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

return {
  tags = find_tags,
  backlinks = find_backlinks,
  links = find_links,
  list_tags = list_tags,
  _prepare_opts = prepare_search_opts,
}
