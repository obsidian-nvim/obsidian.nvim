local util = require "obsidian.util"
local log = require "obsidian.log"
local RefTypes = require("obsidian.search").RefTypes
local api = require "obsidian.api"
local search = require "obsidian.search"

---@param picker obsidian.Picker
---@param note obsidian.Note
---@param opts { anchor: string|?, block: string|? }|?
local function collect_backlinks(picker, note, opts)
  opts = opts or {}

  search.find_backlinks_async(note, function(backlinks)
    if vim.tbl_isempty(backlinks) then
      if opts.anchor then
        log.info("No backlinks found for anchor '%s' in note '%s'", opts.anchor, note.id)
      elseif opts.block then
        log.info("No backlinks found for block '%s' in note '%s'", opts.block, note.id)
      else
        log.info("No backlinks found for note '%s'", note.id)
      end
      return
    end

    local entries = {}

    for _, backlink in ipairs(backlinks) do
      entries[#entries + 1] = {
        value = { path = backlink.path, line = backlink.line },
        filename = tostring(backlink.path),
        lnum = backlink.line,
      }
    end

    ---@type string
    local prompt_title
    if opts.anchor then
      prompt_title = string.format("Backlinks to '%s%s'", note.id, opts.anchor)
    elseif opts.block then
      prompt_title = string.format("Backlinks to '%s#%s'", note.id, util.standardize_block(opts.block))
    else
      prompt_title = string.format("Backlinks to '%s'", note.id)
    end

    vim.schedule(function()
      picker:pick(entries, {
        prompt_title = prompt_title,
        callback = function(value)
          api.open_buffer(value.path, { line = value.line })
        end,
      })
    end)
  end, { search = { sort = true, anchor = opts.anchor, block = opts.block } })
end

return function()
  local picker = assert(Obsidian.picker)
  if not picker then
    log.err "No picker configured"
    return
  end

  local cur_link, link_type = api.cursor_link()

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

    search.resolve_note_async(location, function(note)
      if not note then
        return log.err("No notes matching '%s'", location)
      else
        return collect_backlinks(picker, note, opts)
      end
    end)
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
      collect_backlinks(picker, note, opts)
    end
  end
end
