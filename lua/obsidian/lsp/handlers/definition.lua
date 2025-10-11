local Note = require "obsidian.note"
local util = require "obsidian.util"
local search = require "obsidian.search"
local api = require "obsidian.api"
local log = require "obsidian.log"
local RefTypes = search.RefTypes

--- TODO: open_strategy

---@param _ lsp.DefinitionParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(_, handler)
  local link = api.cursor_link()

  if not link then
    return -- TODO: ?
  end

  local function jump_to_note(note, block_link, anchor_link)
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
    -- TODO: open a window before jumping?

    handler(nil, {
      {
        uri = note:uri(),
        range = {
          start = { line = line, character = 0 },
          ["end"] = { line = line, character = 0 },
        },
      },
    })
  end

  local function create_new_note(location, name)
    if api.confirm("Create new note '" .. location .. "'?") then
      ---@type string|?, string[]
      local id, aliases
      if name == location then
        aliases = {}
      else
        aliases = { name }
        id = location
      end

      local note = Note.create { title = name, id = id, aliases = aliases }

      jump_to_note(note)
    else
      return log.warn "Aborted"
    end
  end

  local location, name, link_type = util.parse_link(link, {
    include_naked_urls = true,
    include_file_urls = true,
  })

  if not location then
    return
  end

  if link_type == RefTypes.NakedUrl then
    return Obsidian.opts.follow_url_func(location)
  elseif link_type == RefTypes.FileUrl then
    return vim.cmd("edit " .. vim.uri_to_fname(location))
  elseif link_type == RefTypes.Wiki or link_type == RefTypes.WikiWithAlias or link_type == RefTypes.Markdown then
    local _, _, location_type = util.parse_link(location, { include_naked_urls = true, include_file_urls = true })
    if util.is_img(location) then -- TODO: include in parse_link
      local path = Obsidian.dir / location
      return Obsidian.opts.follow_img_func(tostring(path))
    elseif location_type == RefTypes.NakedUrl then
      return Obsidian.opts.follow_url_func(location)
    elseif location_type == RefTypes.FileUrl then
      return vim.cmd("edit " .. vim.uri_to_fname(location))
    else
      local block_link, anchor_link
      location, block_link = util.strip_block_links(location)
      location, anchor_link = util.strip_anchor_links(location)

      local notes = search.resolve_note(location, {})
      if vim.tbl_isempty(notes) then
        create_new_note(location, name)
      elseif #notes == 1 then
        jump_to_note(notes[1], block_link, anchor_link)
      elseif #notes > 1 then
        Obsidian.picker:pick_note(notes, {
          callback = function(note)
            jump_to_note(note, block_link, anchor_link)
          end,
        })
      end
    end
  else
    log.err "link type not supported"
  end
end
