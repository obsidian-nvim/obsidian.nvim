local obsidian = require "obsidian"
local search = obsidian.search
local util = obsidian.util
local log = obsidian.log
local api = obsidian.api
local Note = obsidian.Note

---@param note obsidian.Note
---@param block_link string?
---@param anchor_link string?
---@return lsp.Location
local function note_to_location(note, block_link, anchor_link)
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
    return note_to_location(note)
  else
    return obsidian.log.warn "Aborted"
  end
end

---@type table<obsidian.search.RefTypes, function>
local handlers = {}

handlers.NakedUrl = function(location)
  -- TODO: Obsidian.opts.open.func
  Obsidian.opts.follow_url_func(location)
  return nil
end

handlers.FileUrl = function(location)
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

handlers.Wiki = function(location, name)
  local _, _, location_type = util.parse_link(location, { exclude = { "Tag", "BlockID" } })
  if util.is_img(location) then -- TODO: include in parse_link
    local path = api.resolve_image_path(location)
    -- TODO: Obsidian.opts.open.func
    Obsidian.opts.follow_img_func(tostring(path))
    return nil
  elseif handlers[location_type] then
    return handlers[location_type](location, name)
  else
    local block_link, anchor_link
    location, block_link = util.strip_block_links(location)
    location, anchor_link = util.strip_anchor_links(location)

    local notes = search.resolve_note(location, {
      notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
    })
    if vim.tbl_isempty(notes) then
      local loc = create_new_note(location, name)
      return { loc }
    elseif #notes == 1 then
      return { note_to_location(notes[1], block_link, anchor_link) }
    elseif #notes > 1 then
      local locations = vim
        .iter(notes)
        :map(function(note)
          return note_to_location(note, block_link, anchor_link)
        end)
        :totable()
      return locations
    end
  end
end

handlers.WikiWithAlias = handlers.Wiki
handlers.Markdown = handlers.Wiki

handlers.HeaderLink = function(location)
  local note = api.current_note(0, { collect_anchor_links = true })
  if not note or vim.tbl_isempty(note.anchor_links) then
    return
  end
  local anchor_obj = note:resolve_anchor_link(location)
  if not anchor_obj then
    return
  end
  local line = anchor_obj.line - 1
  return {
    {
      uri = vim.uri_from_fname(tostring(note.path)),
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
  }
end

handlers.BlockLink = function(location)
  local note = api.current_note(0, { collect_blocks = true })
  if not note or vim.tbl_isempty(note.blocks) then
    return
  end
  local block_obj = note:resolve_block(location)
  if not block_obj then
    return
  end
  local line = block_obj.line - 1
  return {
    {
      uri = vim.uri_from_fname(tostring(note.path)),
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
  }
end

handlers.MailtoUrl = function(location)
  -- TODO: Obsidian.opts.open.func
  vim.ui.open(location)
  return nil
end

return {
  follow_link = function(link, callback)
    local location, name, link_type = util.parse_link(link, { exclude = { "Tag", "BlockID" } })

    if not location then
      return callback(nil, {})
    end

    local handler = handlers[link_type]

    if not handler then
      return log.err("unsupported link format", link_type)
    end

    local lsp_locations = handler(location, name)

    if lsp_locations and util.islist(lsp_locations) then
      callback(nil, lsp_locations)
    end
  end,
}
