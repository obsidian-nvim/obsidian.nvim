local obsidian = require "obsidian"
local search = obsidian.search
local RefTypes = obsidian.search.RefTypes
local util = obsidian.util

---@param note obsidian.Note
---@param block_link string?
---@param anchor_link string?
---@return lsp.Location
local function note_to_loaction(note, block_link, anchor_link)
  ---@type integer|?, obsidian.note.Block|?, obsidian.note.HeaderAnchor|?
  local line, block_match, anchor_match
  if block_link then
    block_match = note:resolve_block(block_link)
    if block_match then
      line = block_match.line
    end
  elseif anchor_link then
    anchor_match = note:resolve_anchor_link(anchor_link)
    if anchor_match then
      line = anchor_match.line
    end
  end

  line = line and line - 1 or 0

  return {
    uri = note:uri(),
    range = {
      start = { line = line, character = 0 },
      ["end"] = { line = line, character = 0 },
    },
  }
end

---@param location string
---@param name string
---@return lsp.Location?
local function create_new_note(location, name)
  local Note = require "obsidian.note"
  if obsidian.api.confirm("Create new note '" .. location .. "'?") then
    ---@type string|?, string[]
    local id, aliases
    if name == location then
      aliases = {}
    else
      aliases = { name }
      id = location
    end

    local note = Note.create { title = name, id = id, aliases = aliases }
    return note_to_loaction(note)
  else
    return obsidian.log.warn "Aborted"
  end
end

---@type table<string, function>
local handlers = {}

handlers[RefTypes.NakedUrl] = function(location)
  return Obsidian.opts.follow_url_func(location)
end

handlers[RefTypes.FileUrl] = function(location)
  local line = 0 -- TODO: :lnum?
  return {
    {
      uri = location,
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
  }
end

handlers[RefTypes.Wiki] = function(location, name)
  local _, _, location_type = util.parse_link(location, { include_naked_urls = true, include_file_urls = true })
  if util.is_img(location) then -- TODO: include in parse_link
    local path = Obsidian.dir / location
    return Obsidian.opts.follow_img_func(tostring(path))
  elseif handlers[location_type] then
    return handlers[location_type](location, name)
  else
    local block_link, anchor_link
    location, block_link = util.strip_block_links(location)
    location, anchor_link = util.strip_anchor_links(location)

    local notes = search.resolve_note(location, {})
    if vim.tbl_isempty(notes) then
      local loc = create_new_note(location, name)
      return { loc }
    elseif #notes == 1 then
      return { note_to_loaction(notes[1], block_link, anchor_link) }
    elseif #notes > 1 then
      local locations = vim
        .iter(notes)
        :map(function(note)
          return note_to_loaction(note, block_link, anchor_link)
        end)
        :totable()
      return locations
    end
  end
end

handlers[RefTypes.WikiWithAlias] = handlers.Wiki
handlers[RefTypes.Markdown] = handlers.Wiki

return {
  follow_link = function(link, callback)
    local location, name, link_type = util.parse_link(link, {
      include_naked_urls = true,
      include_file_urls = true,
    })

    if not location then
      return callback(nil, {})
    end

    local lsp_locations = handlers[link_type](location, name)

    if lsp_locations and util.islist(lsp_locations) then
      callback(nil, lsp_locations)
    end
  end,
}
