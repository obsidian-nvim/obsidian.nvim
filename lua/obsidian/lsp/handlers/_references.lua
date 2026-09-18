local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"
local parse_block_id = require "obsidian.parse.block_id"
local parse_refs = require "obsidian.parse.refs"
local header = require "obsidian.parse.header"

---@param match obsidian.BacklinkMatch
---@return lsp.Location
local function backlink_to_lsp_location(match)
  local start_col = match.start or 0
  local end_col = match["end"] or start_col
  return {
    uri = vim.uri_from_fname(tostring(match.path)),
    range = {
      start = { line = match.line - 1, character = start_col },
      ["end"] = { line = match.line - 1, character = end_col },
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

local function handle_note_ref(link, callback, request_opts)
  local ref = assert(parse_refs.parse(link), "failed to parse link")
  local location = ref.target
  local anchor_link = ref.anchor
  local block_link = ref.block

  local opts = { anchor = anchor_link, block = block_link, dir = request_opts.dir }

  local function find_backlinks(note)
    if note == nil then
      opts.refs = { location }
    end
    search.find_backlinks_async(note, function(backlink_matches)
      callback(vim.tbl_map(backlink_to_lsp_location, backlink_matches))
    end, opts)
  end

  if location == "" and (anchor_link or block_link) then
    local note = api.current_note(request_opts.bufnr, {
      collect_anchor_links = anchor_link ~= nil,
      collect_blocks = block_link ~= nil,
    })
    if not note then
      return log.err "Current buffer does not appear to be a note inside the vault"
    end
    find_backlinks(note)
  elseif anchor_link or block_link then
    search.resolve_note_async(location, function(notes)
      find_backlinks(#notes == 1 and notes[1] or nil)
    end, {
      dir = request_opts.dir,
      buf_dir = request_opts.buf_dir,
      notes = {
        collect_anchor_links = anchor_link ~= nil,
        collect_blocks = block_link ~= nil,
      },
    })
  else
    find_backlinks(nil)
  end
end

local handle_footnote = function(link, callback, opts)
  local footnotes = require "obsidian.footnotes"
  local parsed_ref = assert(parse_refs.parse(link), "failed to parse footnote")
  local id = parsed_ref.target

  local bufnr = opts.bufnr
  local uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr))

  local locations = vim.tbl_map(function(ref)
    return {
      uri = uri,
      range = {
        start = { line = ref.lnum - 1, character = ref.start_col },
        ["end"] = { line = ref.lnum - 1, character = ref.end_col },
      },
    }
  end, footnotes.find_refs(bufnr, id))

  callback(locations)
end

local function handle_tag(tag, callback, opts)
  search.find_tags_async(tag, function(tag_locs)
    local lsp_locs = vim.tbl_map(tag_loc_to_lsp_location, tag_locs)
    callback(lsp_locs)
  end, { dir = opts.dir })
end

local function collect_current_note(link, link_type, callback, opts)
  local anchor
  local block

  if link and link_type == "block_id" then
    block = link
  end

  -- Check if cursor is on a header, if so and header parsing is enabled, use that anchor.
  if Obsidian.opts.backlinks.parse_headers then
    local line = vim.api.nvim_buf_get_lines(opts.bufnr, opts.position.line, opts.position.line + 1, false)[1] or ""
    local header_match = header.parse(line)
    local first_byte = line:find "%S"
    if header_match and first_byte then
      local marker = Range.new(opts.position.line, first_byte - 1, opts.position.line, first_byte)
      if not BufferDocument.get(opts.bufnr):intersects(marker, Document.BODY_EXCLUSIONS) then
        anchor = header_match.anchor
      end
    end
  end

  local note = api.current_note(opts.bufnr, {
    collect_anchor_links = anchor ~= nil,
    collect_blocks = block ~= nil,
  })

  if not note then
    return log.err "Current buffer does not appear to be a note inside the vault"
  end

  search.find_backlinks_async(note, function(backlink_matches)
    callback(nil, vim.tbl_map(backlink_to_lsp_location, backlink_matches))
  end, { anchor = anchor, block = block, dir = opts.dir })
end

---@param include_tag boolean|?
---@return string|?
---@return obsidian.parse.RefKind|"tag"|"block_id"|?
local function cursor_ref(include_tag, opts)
  local link, link_type = api.cursor_link(opts.bufnr, opts.position)
  if link and link_type then
    return link, link_type
  end

  local line = vim.api.nvim_buf_get_lines(opts.bufnr, opts.position.line, opts.position.line + 1, false)[1] or ""
  local cur_col = opts.position.character
  local document = BufferDocument.get(opts.bufnr)
  for _, block in ipairs(parse_block_id.extract(line, { row = opts.position.line, lexical = true })) do
    if
      block.range.start_col <= cur_col
      and cur_col < block.range.end_col
      and not document:intersects(block.range, Document.BODY_EXCLUSIONS)
    then
      return block.raw, "block_id"
    end
  end

  if include_tag ~= false then
    local tag = api.cursor_tag(opts.bufnr, opts.position)
    if tag then
      return tag, "tag"
    end
  end
end

---@param link string|?
---@param opts { tag: boolean, bufnr: integer|?, position: lsp.Position|?, dir: string|obsidian.Path|?, buf_dir: string|obsidian.Path|? }
---@param callback fun(_:any, locations: lsp.Location[])
return function(link, opts, callback)
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.position = opts.position
    or (function()
      local cursor = vim.api.nvim_win_get_cursor(0)
      return { line = cursor[1] - 1, character = cursor[2] }
    end)()
  local source_path = vim.api.nvim_buf_get_name(opts.bufnr)
  opts.dir = opts.dir or api.resolve_workspace_dir(source_path)
  opts.buf_dir = opts.buf_dir or (source_path ~= "" and vim.fs.dirname(source_path) or nil)

  local link_type
  if link then
    local ref = parse_refs.parse(link)
    link_type = ref and ref.kind or nil
  else
    link, link_type = cursor_ref(opts.tag, opts)
  end

  local wrapped_callback = function(locations)
    callback(nil, locations)
  end

  if not link then
    return collect_current_note(nil, nil, callback, opts)
  end

  if link_type == "markdown" or link_type == "wiki" then
    handle_note_ref(link, wrapped_callback, opts)
  elseif link_type == "footnote" then
    handle_footnote(link, wrapped_callback, opts)
  elseif link_type == "tag" then
    handle_tag(link, wrapped_callback, opts)
  else -- block id is handled here
    collect_current_note(link, link_type, callback, opts)
  end
end
