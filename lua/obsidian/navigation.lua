--- Note opening, jump history, and link navigation shared by actions and LSP handlers.
local M = {}
local Range = require "obsidian.range"
local search = require "obsidian.search"
local log = require "obsidian.log"
local api = require "obsidian.api"
local refs_parser = require "obsidian.parse.refs"
local link_parser = require "obsidian.link.parser"
local header = require "obsidian.parse.header"
local block_ids = require "obsidian.parse.block_id"
local uri_util = require "obsidian.uri"
local attachment = require "obsidian.attachment"

---@param range obsidian.Range|lsp.Range|?
---@return obsidian.Range|?
local function normalize_range(range)
  if not range then
    return nil
  elseif range.start_row then
    return range
  elseif range.start then
    -- Obsidian's built-in language server uses UTF-8 positions.
    return Range.from_lsp(range, "utf-8")
  end
end

---@param entry obsidian.picker.Entry|vim.quickfix.entry
---@return obsidian.Range|?
local function entry_range(entry)
  local range = rawget(entry, "range")
  if type(range) == "table" then
    return normalize_range(range)
  end

  local lnum = tonumber(entry.lnum)
  local col = tonumber(entry.col) or 1
  local end_lnum = tonumber(entry.end_lnum)
  local end_col = tonumber(entry.end_col)
  if lnum and end_lnum and end_col then
    local start_row = lnum - 1
    local start_col = math.max(col - 1, 0)
    local end_row = end_lnum - 1
    local normalized_end_col = math.max(end_col - 1, 0)
    ---@cast start_row integer
    ---@cast start_col integer
    ---@cast end_row integer
    ---@cast normalized_end_col integer
    return Range.new(start_row, start_col, end_row, normalized_end_col)
  end
end

--- Open a buffer for the corresponding path.
---
---@param path string|obsidian.Path
---@param opts { line: integer|?, col: integer|?, cmd: string|? }|?
---@return integer bufnr
---@deprecated
M.open_buffer = function(path, opts)
  vim.deprecate("navigation.open_buffer", "navigation.open_note", "4.0.0", "obsidian.nvim")
  opts = opts or {}
  return M.open_note({
    filename = tostring(path),
    lnum = opts.line,
    col = opts.col and opts.col + 1,
  }, opts.cmd)
end

--- Open a quickfix entry in buffer, with open strategy
---@param entry obsidian.picker.Entry|vim.quickfix.entry|string
---@param cmd string?
---@return integer
M.open_note = function(entry, cmd)
  local path
  if type(entry) == "string" then
    path = entry
  else
    path = entry.filename
  end
  cmd = vim.trim(cmd and cmd or "e")

  ---@type integer|?
  local result_bufnr

  -- Check for buffer in windows and use 'drop' command if one is found.
  for _, winnr in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == tostring(path) then
      cmd = "drop"
      result_bufnr = bufnr
      break
    end
  end

  vim.cmd(string.format("%s %s", cmd, vim.fn.fnameescape(tostring(path))))
  if type(entry) == "table" and entry.lnum then
    local lnum = tonumber(entry.lnum)
    local col = math.max((tonumber(entry.col) or 1) - 1, 0)
    ---@cast lnum integer
    ---@cast col integer
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  end

  if not result_bufnr then
    result_bufnr = vim.api.nvim_get_current_buf()
  end

  -- Blink the target range, e.g. the full section of an anchor/block link.
  if type(entry) == "table" then
    local range = entry_range(entry)
    if range and not Range.is_empty(range) then
      api.blink(range, result_bufnr)
    end
  end

  return result_bufnr
end

local function record_jump()
  vim.cmd "normal! m'"
  local from = { vim.fn.bufnr "%", vim.fn.line ".", vim.fn.col ".", 0 }
  vim.fn.settagstack(vim.api.nvim_get_current_win(), {
    items = { { tagname = vim.fn.expand "<cword>", from = from } },
  }, "t")
end

--- Navigate to a note or quickfix result, recording the source like an LSP jump.
--- Use open_note instead for ordinary file opening (e.g. newly created notes).
---@param entry obsidian.picker.Entry|vim.quickfix.entry|string
---@param cmd string? Ex opening strategy for splits; defaults to the current window.
---@return integer? bufnr
M.jump_to_note = function(entry, cmd)
  local path = type(entry) == "string" and entry or entry.filename
  if path == "" then
    -- Unnamed buffers (e.g. scratch notes in tests) have no file URI.
    if type(entry) == "table" and entry.lnum then
      local row = tonumber(entry.lnum)
      local col = math.max((tonumber(entry.col) or 1) - 1, 0)
      ---@cast row integer
      ---@cast col integer
      record_jump()
      vim.api.nvim_win_set_cursor(0, { row, col })
    end
    return vim.api.nvim_get_current_buf()
  end
  local location = type(entry) == "table" and entry.user_data or nil
  if type(location) ~= "table" or not (location.uri or location.targetUri) then
    local range = type(entry) == "table" and entry_range(entry) or nil
    if not range and type(entry) == "table" and entry.lnum then
      local row = tonumber(entry.lnum)
      local col = math.max((tonumber(entry.col) or 1) - 1, 0)
      ---@cast row integer
      ---@cast col integer
      range = Range.new(row - 1, col, row - 1, col)
    end
    location = { uri = vim.uri_from_fname(tostring(path)), range = range and Range.to_lsp(range, "utf-8") or nil }
  end

  local bufnr = vim.uri_to_bufnr(location.uri or location.targetUri)
  local target_visible = #vim.fn.win_findbuf(bufnr) > 0
  if not cmd or vim.trim(cmd) == "e" or target_visible then
    local source_buf = vim.api.nvim_get_current_buf()
    local reuse_win = false
    if target_visible and source_buf ~= bufnr then
      -- Keep the jump in the source window's jumplist when it can switch buffers.
      local bufhidden = vim.bo.bufhidden
      local can_hide = bufhidden == "hide" or (bufhidden == "" and vim.o.hidden)
      reuse_win = vim.wo.winfixbuf or (vim.bo.modified and not can_hide and #vim.fn.win_findbuf(source_buf) == 1)
    end
    if vim.lsp.util.show_document(location, "utf-8", { reuse_win = reuse_win }) then
      local range = type(entry) == "table" and entry_range(entry) or nil
      if range and not Range.is_empty(range) then
        api.blink(range)
      end
      return vim.api.nvim_get_current_buf()
    end
    return nil
  end

  -- show_document cannot open a split. Mirror its source mark and tagstack
  -- before delegating the configured Ex command to open_note.
  record_jump()
  return M.open_note(entry, cmd)
end

---Get the strategy for opening notes
---
---@param opt obsidian.config.OpenStrategy
---@return string
M.get_open_strategy = function(opt)
  local OpenStrategy = require("obsidian.types").OpenStrategy

  -- either 'leaf', 'row' for vertically split windows, or 'col' for horizontally split windows
  local cur_layout = vim.fn.winlayout()[1]

  if vim.startswith(OpenStrategy.tab, opt) then
    return "tabedit "
  elseif vim.startswith(OpenStrategy.hsplit, opt) then
    if cur_layout ~= "col" then
      return "split "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit, opt) then
    if cur_layout ~= "row" then
      return "vsplit "
    else
      return "e "
    end
  elseif vim.startswith(OpenStrategy.vsplit_force, opt) then
    return "vsplit "
  elseif vim.startswith(OpenStrategy.hsplit_force, opt) then
    return "split "
  elseif vim.startswith(OpenStrategy.current, opt) then
    return "e "
  else
    log.err("undefined open strategy '%s'", opt)
    return "e "
  end
end

local function open_uri(uri, scheme)
  if scheme == "obsidian" then
    local parsed = uri_util.parse(uri)
    if
      parsed
      and uri_util.is_mutating(parsed)
      and api.confirm(("Run file-modifying URI action? %s"):format(uri)) ~= "Yes"
    then
      return
    end
    uri_util.handle(uri)
  elseif vim.list_contains(Obsidian.opts.open.schemes or {}, scheme) then
    vim.ui.open(uri)
  else
    local choice = api.confirm(("Open external link? %s"):format(uri))

    if choice == "Yes" then
      vim.ui.open(uri)
    end
  end
end

---@class obsidian.navigation.FollowLinkOpts
---@field range [integer, integer]|?
---@field label string|?
---@field bufnr integer|?
---@field cursor_row integer|?
---@field anchor string|?
---@field block string|?
---@field open_strategy obsidian.config.OpenStrategy|?

--- Open an attachment with the system default application.
---@param location string Attachment path or link target.
local function open_attachment(location, callback, opts)
  attachment._resolve_async(location, { bufnr = opts and opts.bufnr }, function(path, err)
    if path and not err then
      vim.ui.open(path)
    end
    callback {}
  end)
end

---@param location string
---@param callback function
---@param opts obsidian.navigation.FollowLinkOpts|?
local function resolve_note(location, callback, opts)
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
    local resolved_notes = notes
    if block_link then
      resolved_notes = vim.tbl_filter(function(note)
        return not vim.tbl_isempty(note.blocks or {}) and note:resolve_block(block_link) ~= nil
      end, resolved_notes)
    end

    if anchor_link then
      resolved_notes = vim.tbl_filter(function(note)
        return not vim.tbl_isempty(note.anchor_links or {}) and note:resolve_anchor_link(anchor_link) ~= nil
      end, resolved_notes)
    end

    if vim.tbl_isempty(resolved_notes) and not vim.tbl_isempty(notes) then
      log.warn("Link target '%s' does not exist in note '%s'", block_link or anchor_link, location)
      resolved_notes = notes
      block_link, anchor_link = nil, nil
    end

    if vim.tbl_isempty(resolved_notes) then
      opts.anchor = raw_anchor ~= nil and link_parser.format("", raw_anchor) or nil
      opts.block = raw_block ~= nil and link_parser.format("", nil, raw_block) or nil
      api.create_new_note(location, callback, opts)
    elseif #resolved_notes == 1 then
      callback { resolved_notes[1]:_location { block = block_link, anchor = anchor_link } }
    elseif #resolved_notes > 1 then
      local locations = {}
      for _, note in ipairs(resolved_notes) do
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
    open_attachment(location, callback, opts)
  else
    resolve_note(location, callback, opts)
  end
end

local handle_markdown_link = function(location, callback, opts)
  local is_uri, scheme = uri_util.is_uri(location)
  if is_uri then
    open_uri(location, scheme)
    callback {}
  elseif api.is_attachment_path(location) then
    open_attachment(location, callback, opts)
  else
    resolve_note(location, callback, opts)
  end
end

local function open_header_link(location, callback, opts)
  local note = api.current_note(opts.bufnr, { collect_anchor_links = true })
  if not note or vim.tbl_isempty(note.anchor_links or {}) then
    return callback {}
  end
  local anchor_obj = note:resolve_anchor_link(location)
  if not anchor_obj then
    return callback {}
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
    footnotes.create(location, bufnr)
    return callback {}
  end

  local lnum, col = def.lnum, 0
  if def.lnum == cursor_row then
    -- Already on the definition, jump back to the first reference.
    local refs = vim.tbl_filter(function(ref)
      return ref.lnum ~= def.lnum
    end, footnotes.find_refs(bufnr, location))
    if vim.tbl_isempty(refs) then
      log.info("No references found for footnote [^%s]", location)
      return callback {}
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
    return callback {}
  end
  local block_obj = note:resolve_block(location)
  if not block_obj then
    return callback {}
  end
  callback { note:_location { block = location } }
end

--- Resolve a link for definition requests. External links are dispatched directly.
---@param link string
---@param callback fun(err: any, locations: lsp.Location[])
---@param opts obsidian.navigation.FollowLinkOpts?
M.resolve_link = function(link, callback, opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  local ref = refs_parser.parse(link)
  if not ref then
    return callback(nil, {})
  end
  local location, label, link_type = ref.target, ref.label, ref.kind
  if label == nil and link_type == "wiki" then
    label = link_parser.format(ref.target, ref.anchor, ref.block)
  end

  -- URI query delimiters must remain encoded until the scheme-specific parser
  -- processes them. Decoding the whole URI turns values such as `%26` into a
  -- new query parameter.
  local is_uri = uri_util.is_uri(location)
  if not is_uri then
    location = vim.uri_decode(location)
  end
  ---@cast location string

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
  elseif link_type == "markdown" or link_type == "autolink" then
    handle_markdown_link(location, wrapped_callback, opts)
  elseif link_type == "wiki" then
    handle_wiki_link(location, wrapped_callback, opts)
  elseif link_type == "footnote" then
    handle_footnote(location, wrapped_callback, opts)
  else
    return log.err("unsupported link format", link_type)
  end
end

--- Jump to a resolved location, prompting only when there are multiple targets.
---@param locations lsp.Location[]
---@param opts { open_strategy: obsidian.config.OpenStrategy?, prompt: string? }?
M.jump_to_locations = function(locations, opts)
  opts = opts or {}
  local items = vim.lsp.util.locations_to_items(locations, "utf-8")
  if #items == 0 then
    return
  end
  local cmd = M.get_open_strategy(opts.open_strategy or Obsidian.opts.open_notes_in)
  if #items == 1 then
    return M.jump_to_note(items[1], cmd)
  end

  local picker = require "obsidian.picker"
  picker.select(items, {
    prompt = opts.prompt or "Resolve link",
    preview_item = function(entry)
      ---@cast entry obsidian.picker.Entry
      local filename = entry.filename
      ---@cast filename -nil
      local preview = picker.preview_path(filename)
      preview.pos = { entry.lnum or 1, math.max((entry.col or 1) - 1, 0) }
      if entry.end_lnum and entry.end_col then
        preview.pos_end = { entry.end_lnum, math.max(entry.end_col - 1, 0) }
      end
      return preview
    end,
  }, function(choices)
    local entry = choices and choices[1]
    if entry then
      M.jump_to_note(entry, cmd)
    end
  end)
end

--- Follow an explicit link or the link under the cursor, without an LSP round trip.
---@param link string?
---@param opts obsidian.navigation.FollowLinkOpts?
M.follow_link = function(link, opts)
  opts = vim.tbl_extend("force", {}, opts or {})
  local source_buf, source_win, row, col = unpack(api.get_active_window_cursor_location())
  opts.bufnr = opts.bufnr or source_buf
  opts.cursor_row = opts.cursor_row or row
  if not link then
    local found_link, _, range = api.cursor_link(opts.bufnr, { line = opts.cursor_row - 1, character = col })
    link, opts.range = found_link, range
  end
  if not link then
    return log.warn "No link found under cursor"
  end

  M.resolve_link(link, function(err, locations)
    if err then
      return log.err(tostring(err))
    end
    -- A delayed result must not jump from a different position or window.
    local current_buf, current_win, current_row, current_col = unpack(api.get_active_window_cursor_location())
    if current_buf == source_buf and current_win == source_win and current_row == row and current_col == col then
      M.jump_to_locations(locations, opts)
    end
  end, opts)
end

--- Move to the next or previous link, optionally including link suggestion hints.
---@param direction "next"|"prev"
---@param include_hints boolean?
M.nav_link = function(direction, include_hints)
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local note = require("obsidian.note").from_buffer(0)
  ---@type { line: integer, start: integer }[]
  local matches = vim.tbl_map(function(link)
    return { line = link.line, start = link.start }
  end, note:links())
  if include_hints and require("obsidian.cache").is_enabled() then
    for _, hint in ipairs(note:link_suggestions()) do
      matches[#matches + 1] = {
        line = hint.range.start_row + 1,
        start = hint.range.start_col,
      }
    end
    table.sort(matches, function(a, b)
      return a.line < b.line or (a.line == b.line and a.start < b.start)
    end)
  end

  if direction == "next" then
    for i = 1, #matches do
      local match = matches[i]
      if (match.line > cursor_line) or (cursor_line == match.line and cursor_col < match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  elseif direction == "prev" then
    for i = #matches, 1, -1 do
      local match = matches[i]
      if (match.line < cursor_line) or (cursor_line == match.line and cursor_col > match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  end
end

return M
