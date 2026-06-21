local util = require "obsidian.util"
local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"
local parse_block_id = require "obsidian.parse.block_id"

---@param match obsidian.BacklinkMatch
---@return lsp.Location
local function backlink_to_lsp_location(match)
  return {
    uri = vim.uri_from_fname(tostring(match.path)),
    range = {
      start = { line = match.line - 1, character = match.start },
      ["end"] = { line = match.line - 1, character = match["end"] },
    },
  }
end

---@param tag_loc obsidian.TagLocation
---@return lsp.Location
local function tag_loc_to_lsp_location(tag_loc)
  local line = tag_loc.line - 1
  -- BUG: why no tags_start field??
  local st, ed = (tag_loc.tag_start or 1) - 1, (tag_loc.tag_end or 1) - 1
  return {
    uri = vim.uri_from_fname(tostring(tag_loc.path)),
    range = {
      start = { line = line, character = st },
      ["end"] = { line = line, character = ed },
    },
  }
end

local function handle_note_ref(link, callback)
  local location = util.parse_link(link)
  assert(location, "failed to parse link")

  -- Remove block links from the end if there are any.
  ---@type string|?
  local block_link
  location, block_link = util.strip_block_links(location)

  -- Remove anchor links from the end if there are any.
  ---@type string|?
  local anchor_link
  location, anchor_link = util.strip_anchor_links(location)

  local opts = { anchor = anchor_link, block = block_link }

  local function find_backlinks(note)
    if note == nil then
      opts.refs = { location }
    end
    search.find_backlinks_async(note, function(backlink_matches)
      callback(vim.iter(backlink_matches):map(backlink_to_lsp_location):totable())
    end, opts)
  end

  if location == "" and (anchor_link or block_link) then
    local note = api.current_note(0, {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    })
    if not note then
      return log.err "Current buffer does not appear to be a note inside the vault"
    end
    find_backlinks(note)
  elseif anchor_link or block_link then
    search.resolve_note_async(location, function(notes)
      find_backlinks(#notes == 1 and notes[1] or nil)
    end, {
      notes = {
        collect_anchor_links = anchor_link ~= nil,
        collect_blocks = block_link ~= nil,
      },
    })
  else
    find_backlinks(nil)
  end
end

local handle_footnote = function(link, callback)
  local footnotes = require "obsidian.footnotes"
  local id = util.parse_link(link)
  assert(id, "failed to parse footnote")

  local bufnr = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr))

  local locations = vim.tbl_map(function(ref)
    return {
      uri = uri,
      range = {
        start = { line = ref.lnum - 1, character = ref.start_col },
        ["end"] = { line = ref.lnum - 1, character = ref.end_col },
      },
    }
  end, footnotes.find_refs(bufnr, id))

  callback(locations)
end

local function handle_tag(tag, callback)
  search.find_tags_async(tag, function(tag_locs)
    local lsp_locs = vim.tbl_map(tag_loc_to_lsp_location, tag_locs)
    callback(lsp_locs)
  end)
end

local function collect_current_note(link, link_type, callback)
  local anchor
  local block

  if link and link_type == "block_id" then
    block = link
  end

  -- Check if cursor is on a header, if so and header parsing is enabled, use that anchor.
  if Obsidian.opts.backlinks.parse_headers then
    local header_match = util.parse_header(vim.api.nvim_get_current_line())
    if header_match then
      anchor = header_match.anchor
    end
  end

  local note = api.current_note(0, {
    collect_anchor_links = anchor ~= nil,
    collect_blocks = block ~= nil,
  })

  if not note then
    return log.err "Current buffer does not appear to be a note inside the vault"
  end

  search.find_backlinks_async(note, function(backlink_matches)
    callback(nil, vim.iter(backlink_matches):map(backlink_to_lsp_location):totable())
  end, { anchor = anchor, block = block })
end

---@param include_tag boolean|?
---@return string|?
---@return obsidian.parse.RefKind|"tag"|"block_id"
local function cursor_ref(include_tag)
  local link, link_type = api.cursor_link()
  if link and link_type then
    return link, link_type
  end

  local line = vim.api.nvim_get_current_line()
  local _, cur_col = unpack(vim.api.nvim_win_get_cursor(0))
  for _, block in ipairs(parse_block_id.extract(line)) do
    if block.range.start_col <= cur_col and cur_col < block.range.end_col then
      return block.raw, "block_id"
    end
  end

  if include_tag ~= false then
    local tag = api.cursor_tag()
    if tag then
      return tag, "tag"
    end
  end
end

---@param link string|?
---@param opts { tag: boolean }
---@param callback fun(_:any, locations: lsp.Location[])
return function(link, opts, callback)
  local link_type
  if link then
    link_type = select(3, util.parse_link(link))
  else
    link, link_type = cursor_ref(opts.tag)
  end

  local wrapped_callback = function(locations)
    callback(nil, locations)
  end

  if not link then
    return collect_current_note(nil, nil, callback)
  end

  if link_type == "markdown" or link_type == "wiki" then
    handle_note_ref(link, wrapped_callback)
  elseif link_type == "footnote" then
    handle_footnote(link, wrapped_callback)
  elseif link_type == "tag" then
    handle_tag(link, wrapped_callback)
  elseif link_type == "block_id" then
    collect_current_note(link, link_type, callback)
  else
    collect_current_note(link, link_type, callback)
  end
end
