local obsidian = require "obsidian"
local search = obsidian.search
local util = obsidian.util
local log = obsidian.log
local api = obsidian.api

local function open_uri(uri, scheme)
  if vim.list_contains(Obsidian.opts.open.schemes or {}, scheme) then
    vim.ui.open(uri)
  else
    local choice = api.confirm(("Open external link? %s"):format(uri))

    if choice == "Yes" then
      vim.ui.open(uri)
    end
  end
end

---@class obsidian.lsp.DefinitionCreateOpts
---@field range [integer, integer]|?
---@field label string|?
---@field bufnr integer|?
---@field cursor_row integer|?
---@field anchor string|?
---@field block string|?

---@param location string
---@param callback function
---@param opts obsidian.lsp.DefinitionCreateOpts|?
local function open_note(location, callback, opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.cursor_row = opts.cursor_row or vim.api.nvim_win_get_cursor(0)[1]

  local block_link, anchor_link, raw_anchor
  location, block_link = util.strip_block_links(location)
  location, anchor_link, raw_anchor = util.strip_anchor_links(location)

  search.resolve_note_async(location, function(notes)
    -- TODO: integrate into resolve_note?
    if block_link then
      notes = vim.tbl_filter(function(note)
        return not vim.tbl_isempty(note.blocks or {}) and note:resolve_block(block_link) ~= nil
      end, notes)
    end

    if anchor_link then
      notes = vim.tbl_filter(function(note)
        return not vim.tbl_isempty(note.anchor_links or {}) and note:resolve_anchor_link(anchor_link) ~= nil
      end, notes)
    end

    if vim.tbl_isempty(notes) then
      opts.anchor = raw_anchor
      opts.block = block_link
      api.create_new_note(location, callback, opts)
    elseif #notes == 1 then
      callback { notes[1]:_location { block = block_link, anchor = anchor_link } }
    elseif #notes > 1 then
      local locations = {}
      for _, note in ipairs(notes) do
        locations[#locations + 1] = note:_location { block = block_link, anchor = anchor_link }
      end
      callback(locations)
    end
  end, {
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })
end

local handle_wiki_link = function(location, callback, opts)
  if api.is_attachment_path(location) then
    api.open_attachment(location)
  else
    open_note(location, callback, opts)
  end
end

local handle_markdown_link = function(location, callback, opts)
  local is_uri, scheme = util.is_uri(location)
  if is_uri then
    open_uri(location, scheme)
  elseif api.is_attachment_path(location) then
    api.open_attachment(location)
  else
    open_note(location, callback, opts)
  end
end

local function open_header_link(location, callback)
  local note = api.current_note(0, { collect_anchor_links = true })
  if not note or vim.tbl_isempty(note.anchor_links or {}) then
    return
  end
  local anchor_obj = note:resolve_anchor_link(location)
  if not anchor_obj then
    return
  end
  callback { note:_location { anchor = location } }
end

local handle_footnote = function(location, callback, _)
  local footnotes = require "obsidian.footnotes"
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]

  local def = footnotes.find_definition(bufnr, location)

  if not def then
    -- Unresolved footnote: prompt for content and insert the definition.
    return footnotes.create(location, bufnr)
  end

  local lnum, col = def.lnum, 0
  if def.lnum == cursor_row then
    -- Already on the definition, jump back to the first reference.
    local refs = vim.tbl_filter(function(ref)
      return ref.lnum ~= def.lnum
    end, footnotes.find_refs(bufnr, location))
    if vim.tbl_isempty(refs) then
      return log.info("No references found for footnote [^%s]", location)
    end
    local ref = refs[1]
    ---@cast ref -nil
    lnum, col = ref.lnum, ref.start_col
  end

  callback {
    {
      uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr)),
      range = {
        start = { line = lnum - 1, character = col },
        ["end"] = { line = lnum - 1, character = col },
      },
    },
  }
end

local function open_block_link(location, callback)
  local note = api.current_note(0, { collect_blocks = true })
  if not note or vim.tbl_isempty(note.blocks or {}) then
    return
  end
  local block_obj = note:resolve_block(location)
  if not block_obj then
    return
  end
  callback { note:_location { block = location } }
end

return {
  follow_link = function(link, callback, opts)
    opts = opts or {}
    local location, label, link_type = util.parse_link(link)
    if not location then
      return callback(nil, {})
    end

    local decoded_location = vim.uri_decode(location)
    if decoded_location then
      ---@cast decoded_location string
      location = decoded_location
    end

    local wrapped_callback = function(lsp_locations)
      if lsp_locations and vim.islist(lsp_locations) then
        callback(nil, lsp_locations)
      end
    end

    opts.label = label
    if vim.startswith(location, "#^") then
      open_block_link(location, wrapped_callback)
    elseif vim.startswith(location, "#") then
      open_header_link(location, wrapped_callback)
    elseif link_type == "markdown" then
      handle_markdown_link(location, wrapped_callback, opts)
    elseif link_type == "wiki" then
      handle_wiki_link(location, wrapped_callback, opts)
    elseif link_type == "footnote" then
      handle_footnote(location, wrapped_callback, opts)
    else
      return log.err("unsupported link format", link_type)
    end
  end,
}
