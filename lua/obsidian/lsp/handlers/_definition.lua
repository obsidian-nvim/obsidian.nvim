local obsidian = require "obsidian"
local search = obsidian.search
local util = obsidian.util
local log = obsidian.log
local api = obsidian.api
local actions = require "obsidian.actions"

local function open_uri(uri, scheme)
  if vim.list_contains(Obsidian.opts.open.schemes, scheme) then
    vim.ui.open(uri)
  else
    local choice = api.confirm(("Open external link? %s"):format(uri))

    if choice == "Yes" then
      vim.ui.open(uri)
    end
  end
end

---@param location string
---@param callback function
---@param opts { range: [integer, integer]|?, label: string|?, bufnr: integer|?, cursor_row: integer|? }|?
---@return lsp.Location?
local function create_new_note(location, callback, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local cursor_row = opts.cursor_row or vim.api.nvim_win_get_cursor(0)[1]

  local has_template = Obsidian.opts.templates.enabled and Obsidian.opts.templates.folder
  local has_unique = Obsidian.opts.unique_note.enabled

  local options = { "&Yes" }
  if has_template then
    table.insert(options, "Yes with &Template")
  end
  if has_unique then
    table.insert(options, "Yes as &Unique Note")
  end
  table.insert(options, "&No")

  local format_options = table.concat(options, "\n")

  local function update_link(note)
    if opts.range and vim.api.nvim_buf_is_valid(bufnr) then
      local new_link = note:format_link { label = opts.label or location, anchor = opts.anchor, block = opts.block }
      vim.api.nvim_buf_set_text(bufnr, cursor_row - 1, opts.range[1] - 1, cursor_row - 1, opts.range[2], { new_link })
    end
  end

  local confirm = api.confirm(("Create new note '%s'?"):format(location), format_options)
  if confirm == "Yes" then
    actions.new(location, function(note)
      update_link(note)
      callback { note:_location() }
    end)
  elseif confirm == "Yes with Template" then
    actions.new_from_template(location, nil, function(note)
      update_link(note)
      callback { note:_location() }
    end)
    return
  elseif confirm == "Yes as Unique Note" then
    local note = require("obsidian.unique").new_unique_note(nil, { title = location })
    if note then
      update_link(note)
      callback { note:_location() }
    end
  else
    return log.warn "Aborted"
  end
end

---@type table<obsidian.search.RefTypes, function>
local handlers = {}

---@param location string
---@param callback function
---@param opts { range: [integer, integer]|?, label: string|?, bufnr: integer|?, cursor_row: integer|? }|?
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
      create_new_note(location, callback, opts)
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
  end, {
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })
end

local function open_attachment(location)
  local path = api.resolve_attachment_path(location)
  vim.ui.open(path)
end

handlers.Wiki = function(location, callback, opts)
  if api.is_attachment_path(location) then
    open_attachment(location)
  else
    open_note(location, callback, opts)
  end
end

handlers.WikiWithAlias = handlers.Wiki

handlers.Markdown = function(location, callback, opts)
  local is_uri, scheme = util.is_uri(location)
  if is_uri then
    open_uri(location, scheme)
  elseif api.is_attachment_path(location) then
    open_attachment(location)
  else
    open_note(location, callback, opts)
  end
end

handlers.HeaderLink = function(location, callback, _)
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

handlers.Footnote = function(location, callback, _)
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
    lnum, col = refs[1].lnum, refs[1].start_col
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

handlers.BlockLink = function(location, callback, _)
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
  follow_link = function(link, callback, opts)
    opts = opts or {}
    -- TODO: write an alternative treesitter link parser that finds, markdown link, wiki link, image embed
    local location, label, link_type = util.parse_link(link, { exclude = { "Tag", "BlockID" } })
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

    opts.label = label
    handler(location, wrapped_callback, opts)
  end,
}
