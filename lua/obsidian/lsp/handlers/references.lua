local util = require "obsidian.util"
local log = require "obsidian.log"
local RefTypes = require("obsidian.search").RefTypes
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param note obsidian.Note
---@param opts { anchor: string|?, block: string|? }
---@return lsp.Location[]
local function collect_backlinks(note, opts)
  return vim
    .iter(note:backlinks { search = { sort = true, anchor = opts.anchor, block = opts.block } })
    :map(function(match)
      return {
        uri = vim.uri_from_fname(tostring(match.path)),
        range = {
          start = { line = match.line - 1, character = match.start },
          ["end"] = { line = match.line - 1, character = match["end"] },
        },
      }
    end)
    :totable()
end

---@param params lsp.ReferenceParams
---@param handler fun(_:any, loactions: lsp.Location[])
return function(params, handler)
  local cur_link, link_type = api.cursor_link()

  local loactions = {} ---@type lsp.Location[]

  if
    cur_link ~= nil
    and link_type ~= RefTypes.NakedUrl
    and link_type ~= RefTypes.FileUrl
    and link_type ~= RefTypes.BlockID
  then
    local location = util.parse_link(cur_link, { include_block_ids = true })
    assert(location, "cursor on a link but failed to parse, please report to repo")

    -- Remove block links from the end if there are any.
    -- TODO: handle block links.
    ---@type string|?
    local block_link
    location, block_link = util.strip_block_links(location)

    -- Remove anchor links from the end if there are any.
    ---@type string|?
    local anchor_link
    location, anchor_link = util.strip_anchor_links(location)

    -- Assume 'location' is current buffer path if empty, like for TOCs.
    if string.len(location) == 0 then
      location = vim.api.nvim_buf_get_name(0)
    end

    local opts = { anchor = anchor_link, block = block_link }

    local note = search.resolve_note(location)

    if not note then
      return log.err("No notes matching '%s'", location)
    else
      loactions = collect_backlinks(note, opts)
    end
  else
    ---@type { anchor: string|?, block: string|? }
    local opts = {}
    ---@type obsidian.note.LoadOpts
    local load_opts = {}

    if cur_link and link_type == RefTypes.BlockID then
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
      loactions = collect_backlinks(note, opts)
    end
  end

  handler(nil, loactions)
end
