local obsidian = require "obsidian"
local search = obsidian.search
local util = obsidian.util
local log = obsidian.log
local api = obsidian.api
local Note = obsidian.Note

local function open_uri(uri, scheme)
  if vim.list_contains(Obsidian.opts.open.schemes, scheme) then
    vim.ui.open(uri)
  else
    local choice = api.confirm(("Open external link? %s"):format(uri))

    if choice == true then
      vim.ui.open(uri)
    end
  end
end

---@param location string
---@param name string
---@param callback function
---@return lsp.Location?
local function create_new_note(location, name, callback)
  local confirm = obsidian.api.confirm(("Create new note '%s'?"):format(location), "&Yes\nYes With &Template\n&No")
  if confirm then
    ---@type string|?, string[]
    local id, aliases
    if name == location then
      aliases = {}
    else
      aliases = { name }
    end
    id = location

    if type(confirm) == "string" and confirm == "Yes With Template" then
      api.new_from_template(name, nil, function(note)
        callback { note:_location() }
      end)
      return
    else
      local note = Note.create { id = id, aliases = aliases }
      callback { note:_location() }
    end
  else
    return obsidian.log.warn "Aborted"
  end
end

---@type table<obsidian.search.RefTypes, function>
local handlers = {}

local function open_note(location, name, callback)
  local block_link, anchor_link
  location, block_link = util.strip_block_links(location)
  location, anchor_link = util.strip_anchor_links(location)

  local notes = search.resolve_note(location, {
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })
  if vim.tbl_isempty(notes) then
    create_new_note(location, name, callback)
  elseif #notes == 1 then
    callback { notes[1]:_location { block = block_link, anchor = anchor_link } }
  elseif #notes > 1 then
    local locations = vim
      .iter(notes)
      :map(function(note)
        return note:_location { block = block_link, anchor = anchor_link }
      end)
      :totable()
    callback(locations)
  end
end

local function open_attachment(location)
  local path = api.resolve_attachment_path(location)
  vim.ui.open(path)
end

handlers.Wiki = function(location, name, callback)
  if api.is_attachment_path(location) then
    open_attachment(location)
  else
    open_note(location, name, callback)
  end
end

handlers.WikiWithAlias = handlers.Wiki

handlers.Markdown = function(location, name, callback)
  local is_uri, scheme = util.is_uri(location)
  if is_uri then
    open_uri(location, scheme)
  elseif api.is_attachment_path(location) then
    open_attachment(location)
  else
    open_note(location, name, callback)
  end
end

handlers.HeaderLink = function(location, _, callback)
  local note = api.current_note(0, { collect_anchor_links = true })
  if not note or vim.tbl_isempty(note.anchor_links) then
    return
  end
  local anchor_obj = note:resolve_anchor_link(location)
  if not anchor_obj then
    return
  end
  local line = anchor_obj.line - 1
  callback {
    {
      uri = vim.uri_from_fname(tostring(note.path)),
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
  }
end

handlers.BlockLink = function(location, _, callback)
  local note = api.current_note(0, { collect_blocks = true })
  if not note or vim.tbl_isempty(note.blocks) then
    return
  end
  local block_obj = note:resolve_block(location)
  if not block_obj then
    return
  end
  local line = block_obj.line - 1
  callback {
    {
      uri = vim.uri_from_fname(tostring(note.path)),
      range = {
        start = { line = line, character = 0 },
        ["end"] = { line = line, character = 0 },
      },
    },
  }
end

return {
  follow_link = function(link, callback)
    -- TODO: write an alternative treesitter link parser that finds, markdown link, wiki link, image embed
    local location, name, link_type = util.parse_link(link, { exclude = { "Tag", "BlockID" } })
    location = vim.uri_decode(location)

    if not location then
      return callback(nil, {})
    end

    local handler = handlers[link_type]

    if not handler then
      return log.err("unsupported link format", link_type)
    end

    local wrapped_callback = function(lsp_locations)
      if lsp_locations and util.islist(lsp_locations) then
        callback(nil, lsp_locations)
      end
    end

    handler(location, name, wrapped_callback)
  end,
}
