local obsidian = require "obsidian"
local search = obsidian.search
local log = obsidian.log
local api = obsidian.api
local actions = require "obsidian.actions"
local refs_parser = require "obsidian.parse.refs"
local link_parser = require "obsidian.link.parser"
local header = require "obsidian.parse.header"
local block_ids = require "obsidian.parse.block_id"
local uri_util = require "obsidian.uri"
local attachment = require "obsidian.attachment"

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

--- Open an attachment with the system default application.
---@param location string Attachment path or link target.
local function open_attachment(location, opts)
  attachment._resolve_async(location, { bufnr = opts and opts.bufnr }, function(path, err)
    if path and not err then
      vim.ui.open(path)
    end
  end)
end

---@param location string
---@param callback function
---@param opts obsidian.lsp.DefinitionCreateOpts|?
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
      local source = vim.api.nvim_buf_get_name(bufnr)
      local new_link = note:format_link {
        label = opts.label or location,
        anchor = opts.anchor,
        block = opts.block,
        dir = source ~= "" and vim.fs.dirname(source) or nil,
      }
      vim.api.nvim_buf_set_text(bufnr, cursor_row - 1, opts.range[1] - 1, cursor_row - 1, opts.range[2], { new_link })
    end
  end

  local source_path = vim.api.nvim_buf_get_name(bufnr)
  local action_opts = { source_path = source_path ~= "" and source_path or nil }
  local workspace_dir = api.resolve_workspace_dir(action_opts.source_path)
  local confirm = api.confirm(("Create new note '%s'?"):format(location), format_options)
  if confirm == "Yes" then
    actions.new(location, function(note)
      update_link(note)
      callback { note:_location() }
    end, action_opts)
  elseif confirm == "Yes with Template" then
    actions.new_from_template(location, nil, function(note)
      update_link(note)
      callback { note:_location() }
    end, action_opts)
    return
  elseif confirm == "Yes as Unique Note" then
    local unique_dir = Obsidian.opts.unique_note.folder and workspace_dir / Obsidian.opts.unique_note.folder
      or workspace_dir
    local note = require("obsidian.unique").new_unique_note(nil, { title = location, dir = unique_dir })
    if note then
      update_link(note)
      callback { note:_location() }
    end
  else
    return log.warn "Aborted"
  end
end

---@param location string
---@param callback function
---@param opts obsidian.lsp.DefinitionCreateOpts|?
local function open_note(location, callback, opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.cursor_row = opts.cursor_row or vim.api.nvim_win_get_cursor(0)[1]

  local raw_anchor, raw_block = opts.anchor, opts.block
  local anchor_link = raw_anchor ~= nil and header.normalize_anchor(raw_anchor) or nil
  local block_link = raw_block ~= nil and block_ids.normalize(raw_block) or nil

  local source = vim.api.nvim_buf_get_name(opts.bufnr)
  local workspace_dir = api.resolve_workspace_dir(source ~= "" and source or nil)

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
      opts.anchor = raw_anchor ~= nil and link_parser.format("", raw_anchor) or nil
      opts.block = raw_block ~= nil and link_parser.format("", nil, raw_block) or nil
      create_new_note(location, callback, opts)
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
    dir = workspace_dir,
    buf_dir = source ~= "" and vim.fs.dirname(source) or nil,
    notes = { collect_anchor_links = anchor_link ~= nil, collect_blocks = block_link ~= nil },
  })
end

local handle_wiki_link = function(location, callback, opts)
  if api.is_attachment_path(location) then
    open_attachment(location, opts)
  else
    open_note(location, callback, opts)
  end
end

local handle_markdown_link = function(location, callback, opts)
  local is_uri, scheme = uri_util.is_uri(location)
  if is_uri then
    open_uri(location, scheme)
  elseif api.is_attachment_path(location) then
    open_attachment(location, opts)
  else
    open_note(location, callback, opts)
  end
end

local function open_header_link(location, callback, opts)
  local note = api.current_note(opts.bufnr, { collect_anchor_links = true })
  if not note or vim.tbl_isempty(note.anchor_links or {}) then
    return
  end
  local anchor_obj = note:resolve_anchor_link(location)
  if not anchor_obj then
    return
  end
  callback { note:_location { anchor = location } }
end

local handle_footnote = function(location, callback, opts)
  local footnotes = require "obsidian.footnotes"
  local bufnr = opts.bufnr
  local cursor_row = opts.cursor_row

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

local function open_block_link(location, callback, opts)
  local note = api.current_note(opts.bufnr, { collect_blocks = true })
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
    local ref = refs_parser.parse(link)
    if not ref then
      return callback(nil, {})
    end
    local location, label, link_type = ref.target, ref.label, ref.kind
    if label == nil and link_type == "wiki" then
      label = link_parser.format(ref.target, ref.anchor, ref.block)
    end

    local decoded_location = vim.uri_decode(location)
    if decoded_location then
      ---@cast decoded_location string
      location = decoded_location
    end

    local decoded_anchor, decoded_block
    location, decoded_anchor, decoded_block = link_parser.parse(location)

    local wrapped_callback = function(lsp_locations)
      if lsp_locations and vim.islist(lsp_locations) then
        callback(nil, lsp_locations)
      end
    end

    opts.label = label
    opts.anchor = ref.anchor ~= nil and (vim.uri_decode(ref.anchor) or ref.anchor) or decoded_anchor
    opts.block = ref.block ~= nil and (vim.uri_decode(ref.block) or ref.block) or decoded_block
    opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
    opts.cursor_row = opts.cursor_row or vim.api.nvim_win_get_cursor(0)[1]
    if opts.block ~= nil and location == "" then
      open_block_link(opts.block, wrapped_callback, opts)
    elseif opts.anchor ~= nil and location == "" then
      open_header_link(opts.anchor, wrapped_callback, opts)
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
