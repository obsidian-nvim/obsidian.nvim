local obsidian = require "obsidian"
local search = obsidian.search
local RefTypes = obsidian.search.RefTypes
local util = obsidian.util
local log = obsidian.log

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
    return note_to_location(note)
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

handlers[RefTypes.Footnote] = function(location, name)
  local count = vim.api.nvim_buf_line_count(0)
  local note = assert(require("obsidian.api").current_note(0))
  local current_line = vim.api.nvim_get_current_line()

  local link_pattern = "%[%^" .. location .. "%]"
  local definition_pattern = link_pattern .. ":"
  local row = unpack(vim.api.nvim_win_get_cursor(0))

  if current_line:match(search.Patterns.Footnote .. ":") then
    return vim
      .iter(vim.api.nvim_buf_get_lines(0, 0, -1, false))
      :enumerate()
      :map(function(idx, str)
        local st, ed = str:find(link_pattern)
        if st and ed and idx ~= row then
          local line = idx - 1
          local col = st - 1
          local col_end = ed - 1
          return {
            uri = note:uri(),
            range = {
              start = { line = line, character = col },
              ["end"] = { line = line, character = col_end },
            },
          }
        end
      end)
      :totable()
  else
    return {
      vim.iter(vim.api.nvim_buf_get_lines(0, 0, -1, false)):enumerate():find(function(idx, str)
        local st, ed = str:find(definition_pattern)
        if st and ed and idx ~= row then
          local line = idx - 1
          local col = st - 1
          local col_end = ed - 1
          return {
            uri = note:uri(),
            range = {
              start = { line = line, character = col },
              ["end"] = { line = line, character = col_end },
            },
          }
        end
      end),
    }
  end

  local locations = {}

  local row = unpack(vim.api.nvim_win_get_cursor(0))

  for i = count, 1, -1 do
    local line_str = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
    local start = line_str:find(link_pattern)
    if start and i ~= row then
      local line = i - 1
      local col = start - 1

      return {
        {
          uri = note:uri(),
          range = {
            start = { line = line, character = col },
            ["end"] = { line = line, character = col },
          },
        },
      }
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
