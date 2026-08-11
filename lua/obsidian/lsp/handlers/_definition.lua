local obsidian = require "obsidian"
local util = obsidian.util
local log = obsidian.log
local api = obsidian.api
local actions = require "obsidian.actions"
local link_resolver = require "obsidian.link"

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
---@field link_type "wiki"|"markdown"|?

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

---@param location string
---@param callback function
---@param opts obsidian.lsp.DefinitionCreateOpts|?
local function open_target(location, callback, opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  opts.cursor_row = opts.cursor_row or vim.api.nvim_win_get_cursor(0)[1]

  link_resolver.resolve_async(location, function(result)
    local target = result.target
    if target.kind == "external" then
      open_uri(target.normalized, target.scheme)
      return
    elseif target.kind == "attachment" then
      local path = result.path or result.predicted_path
      if path then
        vim.ui.open(path)
      end
      return
    elseif target.kind == "file" then
      if result.path then
        vim.ui.open(result.path)
      else
        log.warn("Link target does not exist: %s", target.normalized)
      end
      return
    elseif target.kind ~= "note" then
      return
    end

    local notes = result.notes or {}
    if result.status == "missing" or vim.tbl_isempty(notes) then
      opts.anchor = target.raw_anchor or target.anchor
      opts.block = target.block
      create_new_note(target.normalized, callback, opts)
      return
    end

    local locations = {}
    for _, note in ipairs(notes) do
      locations[#locations + 1] = note:_location { block = target.block, anchor = target.anchor }
    end
    callback(locations)
  end, {
    source_path = vim.api.nvim_buf_get_name(opts.bufnr),
    link_type = opts.link_type,
    notes = {
      collect_anchor_links = location:find("#", 1, true) ~= nil,
      collect_blocks = location:find("#^", 1, true) ~= nil,
    },
  })
end

local function handle_wiki_link(location, callback, opts)
  opts.link_type = "wiki"
  open_target(location, callback, opts)
end

local function handle_markdown_link(location, callback, opts)
  opts.link_type = "markdown"
  open_target(location, callback, opts)
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
