local util = require "obsidian.util"
local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param match obsidian.BacklinkMatch
---@return lsp.Location
local function backlink_to_location(match)
  return {
    uri = vim.uri_from_fname(tostring(match.path)),
    range = {
      start = { line = match.line - 1, character = match.start },
      ["end"] = { line = match.line - 1, character = match["end"] },
    },
  }
end

---@param note obsidian.Note
---@param opts { anchor: string|?, block: string|? }
---@return lsp.Location[]
local function collect_backlinks(note, opts)
  local backlink_matches = note:backlinks { search = { sort = true }, anchor = opts.anchor, block = opts.block }
  return vim.iter(backlink_matches):map(backlink_to_location):totable()
end

---@param _ lsp.ReferenceParams
---@param handler fun(_:any, locations: lsp.Location[])
return function(_, handler)
  local cur_link, link_type = api.cursor_link()

  local locations = {} ---@type lsp.Location[]

  if cur_link ~= nil and link_type ~= "NakedUrl" and link_type ~= "FileUrl" and link_type ~= "BlockID" then
    local location = util.parse_link(cur_link)
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
      return
    else
      local note = notes[1]
      locations = collect_backlinks(note, opts)
    end
  else
    ---@type { anchor: string|?, block: string|? }
    local opts = {}
    ---@type obsidian.note.LoadOpts
    local load_opts = {}

    if cur_link and link_type == "BlockID" then
      opts.block = util.parse_link(cur_link, { include_block_ids = true })
    else
      load_opts.collect_anchor_links = true
    end

    local note = api.current_note(0, load_opts)

    -- Check if cursor is on a header, if so and header parsing is enabled, use that anchor.
    if Obsidian.opts.backlinks.parse_headers then
      local header_match = util.parse_header(vim.api.nvim_get_current_line())
      if header_match then
        opts.anchor = header_match.anchor
      end
    end

    if note == nil then
      log.err "Current buffer does not appear to be a note inside the vault"
    else
      locations = collect_backlinks(note, opts)
    end
  end

  handler(nil, locations)
end
