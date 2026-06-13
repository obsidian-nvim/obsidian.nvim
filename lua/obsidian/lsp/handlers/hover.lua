local api = require "obsidian.api"
local util = require "obsidian.util"
local search = require "obsidian.search"

local M = {}

--- TODO: tag hover should also work on frontmatter
--- TODO: add hover support for bare/autolink URLs once cursor_link can detect them.
--- TODO: hover for attachments

---@type table<obsidian.search.RefTypes, fun(location: string, label: string|?, callback: fun(contents: string))|?>
local handlers = {}

---@param note obsidian.Note
---@param label string|?
---@param anchor_link string|?
---@param block_link string|?
---@return string|?
local function note_preview(note, label, anchor_link, block_link)
  local anchor, block

  if anchor_link then
    anchor = note:resolve_anchor_link(anchor_link)
    if not anchor then
      return nil
    end
  end

  if block_link then
    block = note:resolve_block(block_link)
    if not block then
      return nil
    end
  end

  return note:display_info { label = label, anchor = block and nil or anchor, block = block }
end

---@param location string
---@param label string|?
---@param callback fun(contents: string)
local function preview_note_link(location, label, callback)
  local is_uri, _scheme = util.is_uri(location)
  if is_uri then
    -- TODO: preview remote URLs when hover has a URL metadata/content provider.
    return
  end

  local block_link, anchor_link
  location, block_link = util.strip_block_links(location)
  location, anchor_link = util.strip_anchor_links(location)

  search.resolve_note_async(location, function(notes)
    for _, note in ipairs(notes) do
      local contents = note_preview(note, label, anchor_link, block_link)
      if contents then
        callback(contents)
        return
      end
    end
  end, {
    notes = {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    },
  })
end

handlers.Wiki = preview_note_link
handlers.WikiWithAlias = preview_note_link

handlers.Markdown = function(location, label, callback)
  if api.is_attachment_path(location) then
    return
  else
    preview_note_link(location, label, callback)
  end
end

handlers.HeaderLink = function(location, label, callback)
  local note = api.current_note(0, { collect_anchor_links = true })
  if not note then
    return
  end

  local contents = note_preview(note, label, location, nil)
  if contents then
    callback(contents)
  end
end

handlers.BlockLink = function(location, label, callback)
  local note = api.current_note(0, { collect_blocks = true })
  if not note then
    return
  end

  local contents = note_preview(note, label, nil, location)
  if contents then
    callback(contents)
  end
end

handlers.BlockID = handlers.BlockLink

handlers.Footnote = function(location, _, callback)
  local footnotes = require "obsidian.footnotes"
  local def = footnotes.find_definition(vim.api.nvim_get_current_buf(), location)
  if def then
    callback(("[^%s]: %s"):format(def.id, def.text))
  end
end

handlers.Tag = function(cursor_tag, _, callback)
  search.find_tags_async(cursor_tag, function(tag_locs)
    local notes_lookup = {}
    for _, tag_loc in ipairs(tag_locs) do
      notes_lookup[tostring(tag_loc.note.path)] = true
    end

    local note_count = vim.tbl_count(notes_lookup)
    callback(string.format("**found in %s notes**", note_count))
  end, {})
end

---@param _ lsp.HoverParams
---@param handler fun(_: any, result: lsp.Hover)
return function(_, handler, _)
  local cursor_ref, cursor_ref_type = api.cursor_link()
  local cursor_tag = api.cursor_tag()

  if cursor_ref then
    local location, label, link_type = util.parse_link(cursor_ref, { link_type = cursor_ref_type })
    if not location or not link_type then
      return
    end

    location = vim.uri_decode(location)
    local hover_handler = handlers[link_type]
    if not hover_handler then
      return
    end

    hover_handler(location, label, function(contents)
      handler(nil, { contents = contents })
    end)
  elseif cursor_tag then
    handlers.Tag(cursor_tag, nil, function(contents)
      handler(nil, { contents = contents })
    end)
  else
    vim.notify("No note or tag found", 3)
  end
end
