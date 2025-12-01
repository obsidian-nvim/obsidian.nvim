local util = require "obsidian.util"
local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"

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

---@param note obsidian.Note
---@param opts { anchor: string|?, block: string|? }
---@return lsp.Location[]
local function collect_backlinks(note, opts)
  local backlink_matches = note:backlinks { search = { sort = true }, anchor = opts.anchor, block = opts.block }
  return vim.iter(backlink_matches):map(backlink_to_lsp_location):totable()
end

---@type table<obsidian.search.RefTypes, fun(_: string, callback: fun(locs: lsp.Location[]))|?>
local handlers = {}

handlers.Markdown = function(link, callback)
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

  local notes = search.resolve_note(location)

  if vim.tbl_isempty(notes) then
    log.err("No notes matching '%s'", location)
  else
    local note = notes[1]
    callback(collect_backlinks(note, opts))
  end
end

handlers.Wiki = handlers.Markdown
handlers.WikiWithAlias = handlers.Markdown

handlers.Tag = function(tag, callback)
  local tag_locs = search.find_tags(tag)
  local lsp_locs = vim.tbl_map(tag_loc_to_lsp_location, tag_locs)
  callback(lsp_locs)
end

local function collect_current_note(link, link_type, callback)
  local anchor, block

  if link and link_type == "BlockID" then
    block = util.parse_link(link)
  end

  -- Check if cursor is on a header, if so and header parsing is enabled, use that anchor.
  -- TODO: header should just be matched as a type of "ref" by `parse_link`
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

  callback(nil, collect_backlinks(note, { anchor = anchor, block = block }))
end

---@type obsidian.search.RefTypes[]
local supported_reference_types = {
  Wiki = true,
  WikiWithAlias = true,
  Markdown = true,
  Tag = true,
  -- HeaderLink
  -- BlockLink
}

--- TODO: api.cursor_ref

---@param include_tag boolean|?
---@return string|?
---@return obsidian.search.RefTypes|?
local function cursor_ref(include_tag)
  local link, link_type = api.cursor_link()
  if link and link_type then
    return link, link_type
  elseif include_tag ~= false then
    local tag = api.cursor_tag()
    if tag then
      return tag, "Tag"
    end
  end
end

---@param link string|?
---@param opts { tag: boolean }
---@param callback fun(_:any, locations: lsp.Location[])
return function(link, opts, callback)
  local link_type
  if link then
    _, _, link_type = util.parse_link(link)
  else
    link, link_type = cursor_ref(opts.tag)
  end

  if not link or not link_type or not supported_reference_types[link_type] then
    collect_current_note(link, link_type, callback)
    return
  end

  local wrapped_callback = function(locations)
    callback(nil, locations)
  end

  if handlers[link_type] then
    handlers[link_type](link, wrapped_callback) -- TODO: maybe same as _definition (location, name, callback)
  end
end
