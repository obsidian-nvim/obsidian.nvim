local M = {}
local api = require "obsidian.api"
local cache = require "obsidian.cache"
local log = require "obsidian.log"
local util = require "obsidian.util"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local attachment = require "obsidian.attachment"
local picker = require "obsidian.picker"
local search = require "obsidian.search"
local resolvers = require "obsidian.resolvers"

---@param entry obsidian.PickerEntry
---@return obsidian.ui_select_preview_spec
local function preview_entry(entry)
  local filename = entry.filename
  ---@cast filename - nil
  local preview = util.preview_path(filename)
  local range = rawget(entry, "range")
  ---@cast range lsp.Range?
  if range then
    preview.pos = { range.start.line + 1, range.start.character }
    preview.pos_end = { range["end"].line + 1, range["end"].character }
  elseif entry.lnum then
    preview.pos = { entry.lnum, entry.col and math.max(entry.col - 1, 0) or 0 }
  end
  return preview
end

--- Follow a link. If the link argument is `nil` we attempt to follow a link under the cursor.
---
---@param link string?
---@param opts { open_strategy: obsidian.config.OpenStrategy |? } |?
M.follow_link = function(link, opts)
  opts = opts and opts or {}
  local range
  if not link then
    local cursor_link = { api.cursor_link() }
    link, range = cursor_link[1], cursor_link[3]
  end

  if not link then
    return log.warn "No link found under cursor"
  end

  require("obsidian.lsp.handlers._definition").follow_link(link, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    local cmd = opts.open_strategy or api.get_open_strategy(Obsidian.opts.open_notes_in)
    if #items == 1 then
      api.open_note(items[1], cmd)
    else
      picker.select(items, {
        prompt = "Resolve link",
        preview_item = preview_entry,
      }, function(choices)
        local entry = choices and choices[1]
        if entry then
          api.open_note(entry, cmd)
        end
      end)
    end
  end, { range = range })
end

---@param direction "next" | "prev"
M.nav_link = function(direction)
  -- vim.validate("direction", direction, "string", false, "nav_link must be called with a direction")
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

  local matches = Note.from_buffer(0):links()

  if direction == "next" then
    for i = 1, #matches do
      local match = matches[i]
      if (match.line > cursor_line) or (cursor_line == match.line and cursor_col < match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  end

  if direction == "prev" then
    for i = #matches, 1, -1 do
      local match = matches[i]
      if (match.line < cursor_line) or (cursor_line == match.line and cursor_col > match.start) then
        return vim.api.nvim_win_set_cursor(0, { match.line, match.start })
      end
    end
  end
end

local function has_markdown_folding()
  if vim.g.markdown_folding == 1 then
    return true
  elseif vim.wo.foldmethod == "expr" then
    return true
  end
  return false
end

-- If cursor is on a link, follow the link
-- If cursor is on a tag, show all notes with that tag in a picker
-- If cursor is on a checkbox, toggle the checkbox
-- If cursor is on a heading, cycle the fold of that heading
M.smart_action = function()
  local legacy = Obsidian.opts.legacy_commands
  if
    vim.lsp.inlay_hint
    and type(vim.lsp.inlay_hint.get) == "function"
    and not vim.tbl_isempty(require("obsidian.inlay_hints").get_actionable_obsidian())
  then
    return "<cmd>lua require('obsidian.inlay_hints').accept()<cr>"
  elseif api.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  elseif api.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  elseif has_markdown_folding() and (api.cursor_heading() or api.cursor_frontmatter()) then
    return "za"
  elseif Obsidian.opts.checkbox.enabled and (api.cursor_checkbox() or Obsidian.opts.checkbox.create_new) then
    return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
  else
    return "<CR>"
  end
end

--- Check if we are in node that should not do checkbox operations.
---
---@return boolean
local function no_checkbox()
  return util.in_node {
    "fenced_code_block",
    "minus_metadata",
    --- what other types?
  }
end

---@param states string[]
---@param cur    string | nil
---@return string?
local function next_checkbox_state(states, cur)
  if not states or #states == 0 then
    return cur or " "
  end
  if cur == nil then
    return states[1]
  end

  local idx
  for i, s in ipairs(states) do
    if s == cur then
      idx = i
      break
    end
  end
  if not idx then
    return states[1]
  end

  idx = idx % #states
  return states[idx + 1]
end

---@param line string
---@return string | nil prefix
---@return string | nil rest
local function parse_list_prefix(line)
  local indent, bullet, spaces, rest = line:match "^(%s*)([-+*])(%s+)(.*)$"
  if bullet then
    return indent .. bullet .. spaces, rest
  end

  local indent2, num, delim, spaces2, rest2 = line:match "^(%s*)(%d+)([%.%)])(%s+)(.*)$"
  if num then
    return indent2 .. num .. delim .. spaces2, rest2
  end

  return nil, nil
end

---@param rest string
---@return string | nil state
---@return string | nil ws
---@return string | nil body
local function parse_checkbox_rest(rest)
  local state, ws, body = rest:match "^%[(.)%](%s*)(.*)$"
  if state ~= nil then
    return state, ws, body
  end
  return nil, nil, nil
end

--- Toggle the checkbox on a lnum
---
---@param states string[]      Optional table containing checkbox states (e.g., {" ", "x"}).
---@param lnum   integer | nil Optional line number to toggle the checkbox on. Defaults to the current line.
M._toggle_checkbox = function(states, lnum)
  if no_checkbox() then
    return
  end
  lnum = lnum or unpack(vim.api.nvim_win_get_cursor(0))
  ---@cast lnum integer
  local line = vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1]

  if not line then
    return
  end

  local checkboxes = states or { " ", "x" }

  local prefix, rest = parse_list_prefix(line)
  if prefix and rest then
    local cur_state, ws, body = parse_checkbox_rest(rest)
    if cur_state then
      local next_state = next_checkbox_state(checkboxes, cur_state)
      if next_state == "" then
        line = prefix .. body
      else
        if ws == "" and body ~= "" then
          ws = " "
        end
        line = prefix .. "[" .. next_state .. "]" .. ws .. body
      end
    else
      -- A list item without a checkbox; treat current state as "".
      local next_state = next_checkbox_state(checkboxes, "")
      if next_state ~= "" then
        line = prefix .. "[" .. next_state .. "] " .. rest
      end
      -- If next_state == "", do nothing.
    end
  elseif Obsidian.opts.checkbox.create_new then
    -- Create a new list item, optionally with a checkbox.
    local indent = line:match "^(%s*)" or ""
    local after_indent = line:sub(#indent + 1)
    local next_state = next_checkbox_state(checkboxes, nil)
    if next_state == "" then
      line = indent .. "- " .. after_indent
    else
      line = indent .. "- [" .. next_state .. "] " .. after_indent
    end
  else
    return
  end

  vim.api.nvim_buf_set_lines(0, lnum - 1, lnum, true, { line })
end

--- Toggle checkbox in current line or current visual region or from start to end lnum
---@param start_lnum integer |?
---@param end_lnum   integer |?
M.toggle_checkbox = function(start_lnum, end_lnum)
  local viz = api.get_visual_selection { strict = true }
  local states = Obsidian.opts.checkbox.order
  ---@cast states - nil
  if viz then
    start_lnum, end_lnum = viz.csrow, viz.cerow
  elseif start_lnum == nil or end_lnum == nil then
    local row = unpack(vim.api.nvim_win_get_cursor(0))
    start_lnum, end_lnum = row, row
  end

  for line_nb = start_lnum, end_lnum do
    local current_line = vim.api.nvim_buf_get_lines(0, line_nb - 1, line_nb, false)[1]
    if current_line and (current_line:match "%S" or Obsidian.opts.checkbox.create_new) then
      M._toggle_checkbox(states, line_nb)
    end
  end
end

--- Set the checkbox on the current line to a specific state.
---
---@param state string | nil Optional string of state to set the checkbox to (e.g., " ", "x").
M.set_checkbox = function(state)
  if no_checkbox() then
    return
  end
  if state == nil then
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
      log.err "set_checkbox: unable to get state input"
      return
    end
    ---@cast key - string
    state = string.char(key)
  end

  local found = false
  for _, value in ipairs(Obsidian.opts.checkbox.order or {}) do
    if value == state then
      found = true
    end
  end

  if not found then
    log.err(
      "state passed '"
        .. state
        .. "' is not part of the available states: "
        .. vim.inspect(Obsidian.opts.checkbox.order)
    )
    return
  end

  local cur_line = vim.api.nvim_get_current_line()

  local prefix, rest = parse_list_prefix(cur_line)
  if prefix and rest then
    local cur_state, ws, body = parse_checkbox_rest(rest)
    if state == "" then
      if cur_state then
        cur_line = prefix .. body
      end
    else
      if cur_state then
        if ws == "" and body ~= "" then
          ws = " "
        end
        cur_line = prefix .. "[" .. state .. "]" .. ws .. body
      else
        cur_line = prefix .. "[" .. state .. "] " .. rest
      end
    end
  elseif Obsidian.opts.checkbox.create_new then
    local indent = cur_line:match "^(%s*)" or ""
    local after_indent = cur_line:sub(#indent + 1)
    if state == "" then
      cur_line = indent .. "- " .. after_indent
    else
      cur_line = indent .. "- [" .. state .. "] " .. after_indent
    end
  else
    return
  end

  local line_num = vim.fn.getpos(".")[2]
  ---@cast line_num integer
  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { cur_line })
end

--- Calculate the byte position after a UTF-8 character at the given byte position.
--- This is needed because visual selection cecol points to the start byte of the last
--- selected character, but we need the position after the full character.
---
---@param line     string  The line content
---@param byte_pos integer The 1-indexed byte position of the character start
---@return integer The 1-indexed byte position after the character (exclusive end)
local function get_utf8_char_end(line, byte_pos)
  if not line or byte_pos > #line then
    return byte_pos
  end
  local byte = line:byte(byte_pos)
  if not byte then
    return byte_pos
  end
  -- Determine UTF-8 character byte length from lead byte
  local char_bytes = 1
  if byte >= 240 then -- 11110xxx: 4-byte char
    char_bytes = 4
  elseif byte >= 224 then -- 1110xxxx: 3-byte char
    char_bytes = 3
  elseif byte >= 192 then -- 110xxxxx: 2-byte char
    char_bytes = 2
  end
  return byte_pos + char_bytes
end

local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1

--- Create an LSP TextEdit from a visual selection.
--- The edit uses UTF-8 byte offsets (matching our LSP server's offset_encoding).
---
---@param viz      obsidian.selection The visual selection
---@param new_text string             The replacement text
---@param bufnr    integer?           Buffer number (defaults to current buffer)
---@return lsp.TextDocumentEdit?
local function make_text_edit(viz, new_text, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_buf_get_lines(bufnr, viz.cerow - 1, viz.cerow, false)[1]

  if not line then
    return
  end

  -- Calculate the exclusive end position (byte after the last selected character)
  local end_col = get_utf8_char_end(line, viz.cecol)

  ---@diagnostic disable-next-line: return-type-mismatch TODO: emmylua bug?
  return {
    textDocument = {
      uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(bufnr)),
      version = has_nvim_0_12 and vim.NIL or nil,
    },
    edits = {
      {
        range = {
          -- LSP positions are 0-indexed
          start = { line = viz.csrow - 1, character = viz.cscol - 1 },
          ["end"] = { line = viz.cerow - 1, character = end_col - 1 },
        },
        newText = new_text,
      },
    },
  }
end

--- Replace the visual selection with new text.
--- Returns the text edit that was (or would be) applied.
---
---@param viz      obsidian.selection
---@param new_text string
---@param opts     { apply: boolean? }? Options. apply defaults to true.
---@return lsp.TextDocumentEdit |?
local function replace_selection(viz, new_text, opts)
  opts = opts or {}
  local apply = opts.apply ~= false -- default to true

  local text_edit = make_text_edit(viz, new_text)

  if apply and text_edit then
    vim.lsp.util.apply_workspace_edit({ documentChanges = { text_edit } }, "utf-8")
    require("obsidian.ui").update(0)
  end

  return text_edit
end

M.link = function()
  local viz = api.get_visual_selection()
  if not viz then
    log.err "`Obsidian link` must be called in visual mode"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  local query = viz.selection

  picker.find_notes {
    prompt_title = "Select note to link",
    query = query,
    callback = function(paths)
      local path = paths[1]
      if not path then
        return
      end
      local note = require("obsidian.note").from_file(path)
      replace_selection(viz, note:format_link { label = query })
    end,
  }
end

---@param label string?
M.link_new = function(label)
  local viz = api.get_visual_selection()
  if not viz then
    log.err "`Obsidian link_new` must be called in visual mode"
    return
  elseif #viz.lines ~= 1 then
    log.err "Only in-line visual selections allowed"
    return
  end

  if not label or string.len(label) <= 0 then
    label = viz.selection
  end

  local note = require("obsidian.note").create { id = label }
  replace_selection(viz, note:format_link { label = label })

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"
end

--- Extract the selected text into a new note
--- and replace the selection with a link to the new note.
---@param label string?
M.extract_note = function(label)
  local viz = api.get_visual_selection()
  if not viz then
    log.err "`Obsidian extract_note` must be called in visual mode"
    return
  end

  local content = vim.split(viz.selection, "\n", { plain = true })

  if label ~= nil and string.len(label) > 0 then
    label = vim.trim(label)
  else
    label = api.input "Enter title (optional): "
    if not label then
      log.warn "Aborted"
      return
    elseif label == "" then
      label = nil
    end
  end

  -- create the new note.
  local note = require("obsidian.note").create { id = label, template = Obsidian.opts.note.template }
  note:write()

  -- replace selection with link to new note
  local link = note:format_link()
  replace_selection(viz, link)

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"

  -- add the selected text to the end of the new note
  note:open { sync = true }
  vim.api.nvim_buf_set_lines(0, -1, -1, false, content)
end

--- Create a new note and write it to disk.
---
--- Runs `callback` if provided. The caller decides whether to open the note;
--- this function never opens it.
---
---@param id       string |?
---@param callback fun(note: obsidian.Note) |?
---@param opts? { source_path: string|obsidian.Path|? }
M.new = function(id, callback, opts)
  opts = opts or {}
  if not id then
    id = api.input("Enter id or path (optional): ", { completion = "file" })
    if not id then
      return log.warn "Aborted"
    elseif id == "" then
      id = nil
    end
  end

  local note = Note.create { id = id, template = Obsidian.opts.note.template, source_path = opts.source_path }
  note:write()

  if callback then
    callback(note)
  end
end

--- Create a new note from a template and write it to disk.
---
--- Runs `callback` if provided. The caller decides whether to open the note;
--- this function never opens it.
---
---@param id       string |?
---@param template string |?
---@param callback fun(note: obsidian.Note) |?
---@param opts? { source_path: string|obsidian.Path|? }
M.new_from_template = function(id, template, callback, opts)
  opts = opts or {}
  local workspace = opts.source_path and api.find_workspace(opts.source_path) or nil
  local templates_dir = api.templates_dir(workspace)
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end

  if id ~= nil and template ~= nil then
    local note = Note.create { id = id, template = template, source_path = opts.source_path }
    note:write()
    if callback then
      callback(note)
    end
    return
  end

  picker.find_files {
    prompt_title = "Templates",
    dir = templates_dir,
    no_default_mappings = true,
    callback = function(template_paths)
      local template_path = template_paths[1]
      if not template_path then
        return
      end
      if id == nil or id == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(api.input, "Enter title or path (optional): ", { completion = "file" })
        id = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          return
        elseif safe_title == "" then
          id = nil
        end
      end

      if template_path == nil or template_path == "" then
        log.warn "Aborted"
        return
      end

      ---@type obsidian.Note
      local note = Note.create { id = id, template = template_path, source_path = opts.source_path }
      note:write()

      if callback then
        callback(note)
      end
    end,
  }
end

-- https://help.obsidian.md/plugins/unique-note
---@param timestamp integer |?
---@return obsidian.Note?
M.unique_note = function(timestamp)
  local note = require("obsidian.unique").new_unique_note(timestamp)
  if not note then
    return
  end
  note:open { sync = true }
  return note
end

-- https://help.obsidian.md/plugins/unique-note
---@param timestamp integer |?
---@return string?
M.unique_link = function(timestamp)
  local link = require("obsidian.unique").new_unique_link(timestamp)
  if not link then
    return
  end
  vim.api.nvim_put({ link }, "c", true, true)
  return link
end

---@param src  string?
---@param opts obsidian.AddAttachmentOpts |?
M.add_attachment = function(src, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local add_opts = {
    insert = opts.insert,
    bufnr = bufnr,
    new_name = opts.new_name,
    position = opts.position,
    scope = opts.scope or "actions.add_attachment",
  }
  if not vim.b[bufnr].obsidian_buffer then
    log.warn "Not in an obsidian buffer"
    return
  end

  resolvers.resolve("attachment", {
    bufnr = bufnr,
    source = src,
    intent = "add_attachment",
  }, function(result, err)
    if err then
      return
    end
    if not result or not result.path then
      log.info "Aborted"
      return
    end
    attachment.add(result.path, add_opts)
  end)
end

M.toggle_recording = function()
  require("obsidian.core-plugins.audio_recorder").toggle()
end

---Inspect cursor context and return a description of what would be bookmarked.
---@return { kind: "url"|"block"|"heading"|"note", label: string }?
local function bookmark_context()
  local note = api.current_note(0)

  -- URL under cursor (Markdown link)
  local link, link_type = api.cursor_link()
  if link and link_type == "markdown" then
    local loc = link:match "^%[.-%]%((.*)%)$"
    if loc then
      local is_uri, scheme = util.is_uri(loc)
      if is_uri and (scheme == "http" or scheme == "https") then
        return { kind = "url", label = "URL under cursor" }
      end
    end
  end

  -- Block under cursor
  local line = vim.api.nvim_get_current_line()
  local block = util.parse_block(line)
  if block and note then
    return { kind = "block", label = "block under cursor" }
  end

  -- Heading under cursor
  local heading = api.cursor_heading()
  if heading and note then
    return { kind = "heading", label = "heading under cursor" }
  end

  if note then
    return { kind = "note", label = "current note" }
  end
end

---Bookmark whatever is under the cursor: URL, block, heading; fallback to the current note.
M.add_bookmark = function()
  local Bookmarks = require "obsidian.bookmarks"
  local ctx = bookmark_context()
  if not ctx then
    log.warn "Nothing to bookmark"
    return
  end

  local note = api.current_note(0)
  local ctime = Bookmarks.new_ctime()

  if ctx.kind == "url" then
    local link = api.cursor_link()
    local title = link and link:match "%[(.-)%]" or nil
    local url = link and link:match "^%[.-%]%((.*)%)$" or nil
    if not url then
      return log.warn "No URL under cursor"
    end
    local ok = Bookmarks.add { type = "url", url = url, title = title or url, ctime = ctime }
    if ok then
      log.info("Bookmarked URL: %s", url)
    end
  elseif ctx.kind == "block" and note then
    local line = vim.api.nvim_get_current_line()
    local block = util.parse_block(line)
    local rel = note.path and note.path:vault_relative_path()
    if not rel then
      return log.err "Cannot resolve note path"
    end
    local subpath = "#" .. block
    local ok = Bookmarks.add {
      type = "file",
      path = rel,
      subpath = subpath,
      title = (note.title or note.id or rel) .. " > " .. block,
      ctime = ctime,
    }
    if ok then
      log.info("Bookmarked block: %s", block)
    end
  elseif ctx.kind == "heading" and note then
    local heading = api.cursor_heading()
    local rel = note.path and note.path:vault_relative_path()
    if not rel or not heading then
      return log.err "Cannot resolve heading"
    end
    local ok = Bookmarks.add {
      type = "file",
      path = rel,
      subpath = "#" .. heading.header,
      title = (note.title or note.id or rel) .. " > " .. heading.header,
      ctime = ctime,
    }
    if ok then
      log.info("Bookmarked heading: %s", heading.header)
    end
  elseif ctx.kind == "note" and note then
    local rel = note.path and note.path:vault_relative_path()
    if not rel then
      return log.err "Cannot resolve note path"
    end
    local ok = Bookmarks.add {
      type = "file",
      path = rel,
      title = note.title or note.id or rel,
      ctime = ctime,
    }
    if ok then
      log.info("Bookmarked note: %s", rel)
    end
  end
end

M._bookmark_context = bookmark_context

M.add_property = function()
  local note = assert(api.current_note(0))

  -- HACK: no native way in lua
  -- TODO: complete for existing keys in vault like obsidian app
  -- TODO: complete for values
  vim.cmd [[
  function! ObsidianPropertyComplete()
    return ['aliases', 'tags', 'id']
  endfunction
     ]]

  local key = api.input("key: ", { completion = "customlist,ObsidianPropertyComplete" })
  local value = api.input "value: "

  if not key or not value then
    return log.info "Aborted"
  end

  if vim.trim(key) == "" or vim.trim(value) == "" then
    return log.info "Empty Input"
  end

  if type(value) == "string" and vim.startswith(value, "=") then
    local f = loadstring("return " .. value:sub(2))
    if not f then
      log.err "failed to eval lua value"
      return
    end
    value = f()
  end

  if key == "tags" then
    if type(value) == "table" then
      for _, tag in ipairs(value) do
        note:add_tag(tag)
      end
    elseif type(value) == "string" then
      note:add_tag(value)
    end
  elseif key == "aliases" then
    if type(value) == "table" then
      for _, tag in ipairs(value) do
        note:add_alias(tag)
      end
    elseif type(value) == "string" then
      note:add_alias(value)
    end
  else
    note:add_field(key, value)
  end
  note:update_frontmatter(0)
end

---@param template_name string |?
M.insert_template = function(template_name)
  local templates_dir = api.templates_dir()
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end
  local templates = require "obsidian.templates"

  -- We need to get this upfront before the picker hijacks the current window.
  local insert_location = api.get_active_window_cursor_location()

  local function insert_template(name)
    templates.insert_template {
      type = "insert_template",
      template_name = name,
      templates_dir = templates_dir,
      location = insert_location,
    }
  end

  if template_name ~= nil then
    insert_template(template_name)
    return
  end

  picker.find_files {
    dir = templates_dir,
    callback = function(paths)
      local path = paths[1]
      if path then
        insert_template(path)
      end
    end,
  }
end

---@param buf integer |?
M.start_presentation = function(buf)
  local note = Note.from_buffer(buf)
  require("obsidian.slides").start_presentation(note)
end

---@param symbol lsp.WorkspaceSymbol
---@return obsidian.PickerEntry
local function symbol_to_entry(symbol)
  local range = symbol.location.range
  return {
    filename = vim.uri_to_fname(symbol.location.uri),
    text = symbol.name,
    lnum = range and range.start.line + 1 or nil,
    range = range,
    user_data = symbol.data,
  }
end

---@param query    string |?
---@param callback fun(entry: obsidian.PickerEntry) |?
M.workspace_symbol = function(query, callback)
  query = query or ""
  require "obsidian.lsp.handlers._workspace_symbol"(query, function(symbols)
    local entries = vim.tbl_map(symbol_to_entry, symbols)
    picker.select(entries, {
      prompt = "Workspace Symbols",
      preview_item = preview_entry,
    }, function(items)
      local entry = items and items[1]
      if not entry then
        return
      elseif callback then
        callback(unpack(items))
      else
        api.open_note(entry)
      end
    end)
  end)
end

--- Pick a folder under the vault root.
---@param callback fun(directory: string, text: string)
local function pick_folder(callback)
  local root = tostring(api.resolve_workspace_dir())
  local choices = { { filename = root, text = "/" } }

  ---@diagnostic disable-next-line: param-type-mismatch
  for path, t in vim.fs.dir(root, { depth = math.huge }) do
    if t == "directory" then
      choices[#choices + 1] = { filename = vim.fs.joinpath(root, path), text = path .. "/" }
    end
  end

  picker.select(choices, {
    format_item = function(v)
      return tostring(v.text)
    end,
    preview_item = function(entry)
      return util.preview_path(entry.filename)
    end,
  }, function(items)
    local entry = items[1]
    if entry and entry.filename and entry.text then
      callback(entry.filename, entry.text)
    end
  end)
end

---@param directory string
---@param text      string
local function move_note(directory, text)
  local bufnr = vim.api.nvim_get_current_buf()
  local src = vim.api.nvim_buf_get_name(bufnr)
  local dest = vim.fs.joinpath(directory, vim.fs.basename(src))
  if src == dest then
    return log.info "Note is already in that folder"
  end
  local ok, err = vim.uv.fs_rename(src, dest)
  if not ok then
    return log.err("Failed to move note: " .. (err or "unknown error"))
  end
  require("obsidian.cache").notes.rename(src, dest)
  vim.api.nvim_buf_set_name(bufnr, dest)
  local write_ok, write_err = pcall(function()
    vim.cmd "silent write!"
  end)
  if not write_ok then
    return log.err("Failed to save moved note: " .. (write_err or "unknown error"))
  end
  log.info("Moved note to '%s'", text)
end

M.move_note = function()
  if not vim.b.obsidian_buffer then
    log.info "Not in an obsidian buffer"
    return
  end
  pick_folder(move_note)
end

---@param dst_note obsidian.Note
local function merge_note(dst_note)
  local current_note = api.current_note()
  assert(current_note, "Must be in a note to merge")

  local message = ('Are you sure you want to merge "%s" to "%s"? "%s" will be deleted.'):format(
    current_note.id,
    dst_note.id,
    current_note.id
  )

  if api.confirm(message) == "Yes" then
    dst_note:merge(current_note)
    dst_note:open { sync = true }
    vim.fs.rm(tostring(current_note.path))
    require("obsidian.cache").notes.delete(tostring(current_note.path))
  end
end

---@param dst_note obsidian.Note?
M.merge_note = function(dst_note)
  if dst_note then
    merge_note(dst_note)
  else
    picker.find_notes {
      callback = function(paths)
        local path = paths[1]
        if not path then
          return
        end
        local note = Note.from_file(path)
        merge_note(note)
      end,
    }
  end
end

--- Create a footnote definition, prompting for its content.
--- Used by the completion source to create unresolved footnotes.
---
---@param id             string |?
---@param bufnr          integer |?
---@param restore_cursor [integer, integer] |?
M.footnote_new = function(id, bufnr, restore_cursor)
  require("obsidian.footnotes").create(id, bufnr, restore_cursor)
end

---@param lines string[]
---@param block_id string
---@return boolean
local function contains_block_id(lines, block_id)
  for _, line in ipairs(lines) do
    if util.parse_block(vim.trim(line)) == block_id then
      return true
    end
  end
  return false
end

---@class obsidian.actions.BlockReferenceOpts
---@field target_path string
---@field target_bufnr integer|?
---@field target_range lsp.Range
---@field target_checksum string
---@field block_id string
---@field placement "inline"|"list-item"|"standalone"
---@field indent string|?
---@field source_bufnr integer
---@field source_range lsp.Range
---@field source_text string
---@field placeholder string

--- Add an ID to an unlabeled block and replace the accepted completion with its link.
---@param opts obsidian.actions.BlockReferenceOpts|?
M.block_reference_new = function(opts)
  if not opts or not vim.api.nvim_buf_is_valid(opts.source_bufnr) then
    return
  end

  local source = vim.api.nvim_buf_get_text(
    opts.source_bufnr,
    opts.source_range.start.line,
    opts.source_range.start.character,
    opts.source_range["end"].line,
    opts.source_range["end"].character,
    {}
  )
  if #source ~= 1 or source[1] ~= opts.placeholder then
    return log.warn "Block reference completion is no longer current"
  end

  local target_bufnr = opts.target_bufnr
  if not target_bufnr or not vim.api.nvim_buf_is_valid(target_bufnr) then
    target_bufnr = vim.fn.bufnr(opts.target_path)
  end
  local target_was_loaded = target_bufnr > 0 and vim.api.nvim_buf_is_loaded(target_bufnr)
  if target_bufnr < 1 then
    target_bufnr = vim.fn.bufadd(opts.target_path)
  end
  vim.fn.bufload(target_bufnr)
  if not vim.bo[target_bufnr].modifiable or vim.bo[target_bufnr].readonly then
    return log.warn "Target block is not writable"
  end

  local target_lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
  local normalized_target = vim.tbl_map(util.rstrip_whitespace, target_lines)
  if vim.fn.sha256(table.concat(normalized_target, "\n")) ~= opts.target_checksum then
    return log.warn "Block changed before its reference could be created"
  end

  if contains_block_id(target_lines, opts.block_id) then
    return log.warn "Generated block ID already exists"
  end

  local target =
    vim.api.nvim_buf_get_lines(target_bufnr, opts.target_range.start.line, opts.target_range["end"].line, false)
  if #target == 0 then
    return log.warn "Target block no longer exists"
  end

  local target_line = opts.target_range["end"].line - 1
  local target_character = #target[#target]
  local has_blank_after = target_lines[opts.target_range["end"].line + 1] ~= nil
    and vim.trim(target_lines[opts.target_range["end"].line + 1]) == ""
  local target_text = " " .. opts.block_id
  if opts.placement == "standalone" then
    target_text = "\n\n" .. opts.block_id .. (has_blank_after and "" or "\n")
  elseif opts.placement == "list-item" then
    target_text = "\n" .. (opts.indent or "    ") .. opts.block_id
  end
  local target_edit = {
    range = {
      start = { line = target_line, character = target_character },
      ["end"] = { line = target_line, character = target_character },
    },
    newText = target_text,
  }
  local source_edit = { range = opts.source_range, newText = opts.source_text }

  ---@param edits lsp.TextEdit[]
  ---@param bufnr integer
  ---@return boolean
  local function apply_text_edits(edits, bufnr)
    local ok, err = pcall(vim.lsp.util.apply_text_edits, edits, bufnr, "utf-8")
    if not ok then
      log.err("Failed to apply block reference edit: %s", err)
      return false
    end
    return true
  end

  if target_bufnr == opts.source_bufnr then
    if not apply_text_edits({ target_edit, source_edit }, target_bufnr) then
      return
    end
  else
    if not apply_text_edits({ target_edit }, target_bufnr) then
      return
    end
    if not target_was_loaded then
      local ok, err = pcall(vim.api.nvim_buf_call, target_bufnr, function()
        vim.cmd "silent write"
      end)
      if not ok then
        log.err("Failed to save block ID in '%s': %s", opts.target_path, err)
        return
      end
    end
    if not contains_block_id(vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false), opts.block_id) then
      log.err("Block ID was removed while saving '%s'", opts.target_path)
      return
    end
    if not apply_text_edits({ source_edit }, opts.source_bufnr) then
      return
    end
  end

  if vim.api.nvim_get_current_buf() == opts.source_bufnr then
    local source_line = opts.source_range.start.line
    ---@cast source_line integer
    if
      target_bufnr == opts.source_bufnr
      and target_text:find("\n", 1, true)
      and target_line < opts.source_range.start.line
    then
      source_line = source_line + select(2, target_text:gsub("\n", ""))
    end
    local source_col = opts.source_range.start.character + #opts.source_text
    ---@cast source_col integer
    vim.api.nvim_win_set_cursor(0, { source_line + 1, source_col })
  end
  require("obsidian.ui").update(opts.source_bufnr)
end

---@param bufnr      integer
---@param suggestion obsidian.LinkSuggestion
---@param candidate  obsidian.LinkSuggestionCandidate
local function apply_link_suggestion(bufnr, suggestion, candidate)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local range = suggestion.range
  local current_text =
    vim.api.nvim_buf_get_text(bufnr, range.start_row, range.start_col, range.end_row, range.end_col, {})
  if #current_text ~= 1 or current_text[1] ~= suggestion.text then
    return log.warn "Link suggestion is no longer current"
  end

  vim.api.nvim_buf_set_text(
    bufnr,
    range.start_row,
    range.start_col,
    range.end_row,
    range.end_col,
    { candidate.new_text }
  )
  require("obsidian.ui").update(bufnr)
end

--- Apply the link suggestion under the cursor, selecting a target when the
--- matched note name or alias belongs to more than one note.
---@param suggestion obsidian.LinkSuggestion|?
M.link_suggestion = function(suggestion)
  local bufnr = vim.api.nvim_get_current_buf()
  local note = api.current_note(bufnr, { max_lines = vim.api.nvim_buf_line_count(bufnr) })
  if not note then
    return
  end

  if not suggestion then
    -- TODO: a find_cursor
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    for _, current in ipairs(note:link_suggestions()) do
      local range = current.range
      if
        range.start_row <= row
        and row <= range.end_row
        and (row ~= range.start_row or range.start_col <= col)
        and (row ~= range.end_row or col < range.end_col)
      then
        suggestion = current
        break
      end
    end
    if not suggestion then
      return
    end
  end

  if #suggestion.candidates == 0 then
    log.info "No Link Suggestion Candidates"
    return
  elseif #suggestion.candidates == 1 then
    return apply_link_suggestion(bufnr, suggestion, suggestion.candidates[1])
  end

  picker.select(suggestion.candidates, {
    prompt = "Select link target",
    format_item = function(candidate)
      return candidate.new_text
    end,
    preview_item = function(candidate)
      return util.preview_path(candidate.target_path)
    end,
  }, function(candidates)
    if not candidates or not candidates[1] then
      return
    end
    apply_link_suggestion(bufnr, suggestion, candidates[1])
  end)
end

--- write note to disk, for lsp completion create note
---
---@param note obsidian.Note
---@param scope string|?
M.write_note = function(note, scope)
  -- Make sure `note` is actually an `obsidian.Note` object.
  -- If it gets serialized by server commands, it will lose its metatable.
  if not Note.is_note_obj(note) then
    note = setmetatable(note, Note)
    if note.path then
      note.path = setmetatable(note.path, Path)
    end
  end
  Note._run_creation_lifecycle(note, scope)
  note:write()
end

M.insert_link = function(query)
  picker.find_files {
    query = query,
    no_default_mappings = true,
    callback = function(paths)
      local path = paths[1]
      if not path then
        return
      end
      local note = Note.from_file(path)
      local link = note:format_link()
      vim.api.nvim_put({ link }, "", true, true)
      require("obsidian.ui").update(0)
    end,
  }
end

---@param tag_locations obsidian.TagLocation[]
---@return string[]
local list_tags = function(tag_locations)
  local tags = {}
  for _, tag_loc in ipairs(tag_locations) do
    local tag = tag_loc.tag
    if not tags[tag] then
      tags[tag] = true
    end
  end
  return vim.tbl_keys(tags)
end

---@param tag_locations obsidian.TagLocation[]
---@param tags          string[]
local function gather_tag_picker_list(tag_locations, tags)
  ---@type obsidian.PickerEntry[]
  local entries = {}
  for _, tag_loc in ipairs(tag_locations) do
    for _, tag in ipairs(tags) do
      if tag_loc.tag:lower() == tag:lower() or vim.startswith(tag_loc.tag:lower(), tag:lower() .. "/") then
        local display = string.format("%s [%s] %s", tag_loc.note:display_name(), tag_loc.line, tag_loc.text)
        entries[#entries + 1] = {
          text = display,
          filename = tostring(tag_loc.path),
          lnum = tag_loc.line,
          col = tag_loc.tag_start,
        }
        break
      end
    end
  end
  if vim.tbl_isempty(entries) then
    if #tags == 1 then
      log.warn "Tag not found"
    else
      log.warn "Tags not found"
    end
    return
  end

  vim.schedule(function()
    picker.select(entries, {
      prompt = "#" .. table.concat(tags, ", #"),
      format_item = function(entry)
        return entry.text
      end,
      preview_item = preview_entry,
    }, function(items)
      if not vim.tbl_isempty(items) then
        api.open_note(items[1])
      end
    end)
  end)
end

local function list_tags_async(callback)
  local dir = api.resolve_workspace_dir()

  search.find_tags_async("", function(tag_locations)
    local tags = list_tags(tag_locations)
    callback(tags, tag_locations)
  end, { dir = dir })
end

---@param callback fun(tags: string[], tag_locations: obsidian.TagLocation[])
---@param title    string |?
local function pick_tags(callback, title)
  list_tags_async(function(tags, tag_locations)
    picker.select(tags, {
      prompt = title,
      allow_multiple = true,
      selection_mappings = picker._tag_selection_mappings(),
    }, function(items)
      if not vim.tbl_isempty(items) then
        callback(items, tag_locations)
      end
    end)
  end)
end

---@param tags string[] |?
M.search_tags = function(tags)
  tags = tags or {}
  if vim.tbl_isempty(tags) then
    local tag = api.cursor_tag()
    if tag then
      tags = { tag }
    end
  end

  local dir = api.resolve_workspace_dir()

  if not vim.tbl_isempty(tags) then
    search.find_tags_async(tags, function(tag_locations)
      return gather_tag_picker_list(tag_locations, util.tbl_unique(tags))
    end, { dir = dir })
  else
    pick_tags(function(selected_tags, tag_locations)
      gather_tag_picker_list(tag_locations, selected_tags)
    end)
  end
end

M.insert_tag = function()
  pick_tags(function(tags)
    for i, tag in ipairs(tags) do
      local put_text = "#" .. tag
      if i ~= #tags then
        put_text = put_text .. " "
      end
      vim.api.nvim_put({ put_text }, "", true, true)
    end
  end, "Tag to insert")
end

---@param tag string
local tag_note = function(tag)
  local note = api.current_note()
  if not note then
    log.warn "No note to insert tag"
    return
  end

  if note:add_tag(tag) then
    note:update_frontmatter(note.bufnr)
  else
    log.info "No tags added"
  end
end

M.add_tag = function()
  pick_tags(function(tags)
    for _, tag in ipairs(tags) do
      tag_note(tag)
    end
  end, "Add tags to current note")
end

---@param dir string|obsidian.Path|?
---@return obsidian.Path
local function resolve_health_dir(dir)
  local path = Path.new(dir or Obsidian.dir)
  if not path:is_absolute() then
    path = Obsidian.dir / path
  end
  return path:resolve()
end

---@param path string|obsidian.Path
---@param dir obsidian.Path
---@return boolean
local function path_in_dir(path, dir)
  return util.is_subpath(tostring(Path.new(path):resolve()), tostring(dir))
end

---@param callback fun(graph: obsidian.Graph)
local function with_health_graph(callback)
  if not cache.is_enabled() then
    log.warn "Orphan and broken-link checks require the note cache; set `cache.enabled = true`"
    return
  end

  cache.when_ready(function()
    callback(require("obsidian.graph").from_cache())
  end)
end

---@param dir obsidian.Path
---@return obsidian.Note[]
local function collect_workspace_notes(dir)
  ---@type obsidian.Note[]
  local notes = {}
  for path in api.dir(dir) do
    local ok, note = pcall(Note.from_file, path)
    if ok and note then
      notes[#notes + 1] = note
    end
  end
  return notes
end

---@param note obsidian.Note
---@return boolean
local function note_is_empty(note)
  for _, line in ipairs(note:body_lines()) do
    if vim.trim(line) ~= "" then
      return false
    end
  end
  return true
end

---@param opts? { dir: string|obsidian.Path|? }
M.list_empty_notes = function(opts)
  -- TODO: expand scan scope to include non-note filetypes.
  opts = opts or {}
  local notes = collect_workspace_notes(resolve_health_dir(opts.dir))

  ---@type obsidian.Note[]
  local empty_notes = {}
  for _, note in ipairs(notes) do
    if note_is_empty(note) then
      empty_notes[#empty_notes + 1] = note
    end
  end

  table.sort(empty_notes, function(a, b)
    return tostring(a.path) < tostring(b.path)
  end)

  ---@type vim.quickfix.entry[]
  local items = {}
  for _, note in ipairs(empty_notes) do
    items[#items + 1] = {
      filename = tostring(note.path),
      lnum = 1,
      col = 1,
      text = "Empty file",
    }
  end

  require("obsidian.picker").select(items, { prompt = "Empty Notes" }, require("obsidian.picker.util").open_notes)
end

---@param opts? { dir: string|obsidian.Path|? }
M.list_orphan_files = function(opts)
  opts = opts or {}
  local dir = resolve_health_dir(opts.dir)

  with_health_graph(function(graph)
    local paths = graph:orphan_files()

    ---@type obsidian.Note[]
    local orphan_notes = {}
    for _, path in ipairs(paths) do
      if path_in_dir(path, dir) then
        orphan_notes[#orphan_notes + 1] = Note.from_file(path)
      end
    end

    table.sort(orphan_notes, function(a, b)
      return tostring(a.path) < tostring(b.path)
    end)

    ---@type vim.quickfix.entry[]
    local items = {}
    for _, note in ipairs(orphan_notes) do
      items[#items + 1] = {
        filename = tostring(note.path),
        lnum = 1,
        col = 1,
        text = vim.fs.basename(tostring(note.path)),
      }
    end

    require("obsidian.picker").select(items, { prompt = "Orphan Files" }, require("obsidian.picker.util").open_notes)
  end)
end

---@param opts? { dir: string|obsidian.Path|? }
M.list_broken_links = function(opts)
  opts = opts or {}
  local dir = resolve_health_dir(opts.dir)

  with_health_graph(function(graph)
    local entries = graph:broken_links()

    ---@type vim.quickfix.entry[]
    local items = {}

    for _, entry in ipairs(entries) do
      if path_in_dir(entry.path, dir) then
        items[#items + 1] = {
          filename = entry.path,
          lnum = entry.line,
          col = (entry.col or 1),
          text = entry.raw,
        }
      end
    end

    table.sort(items, function(a, b)
      if a.filename == b.filename then
        if a.lnum == b.lnum then
          return a.col < b.col
        end
        return a.lnum < b.lnum
      end
      return a.filename < b.filename
    end)

    require("obsidian.picker").select(items, { prompt = "Broken Links" }, require("obsidian.picker.util").open_notes)
  end)
end

return M
