local M = {}
local api = require "obsidian.api"
local log = require "obsidian.log"
local util = require "obsidian.util"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local dead_links_analysis = require "obsidian.analysis.dead_links"

--- Follow a link. If the link argument is `nil` we attempt to follow a link under the cursor.
---
---@param link string
---@param opts { open_strategy: obsidian.config.OpenStrategy|? }|?
M.follow_link = function(link, opts)
  opts = opts and opts or {}
  require("obsidian.lsp.handlers._definition").follow_link(link, function(_, locations)
    local items = vim.lsp.util.locations_to_items(locations, "utf-8")
    local cmd = opts.open_strategy or api.get_open_strategy(Obsidian.opts.open_notes_in)
    if #items == 1 then
      api.open_note(items[1], cmd)
    else
      Obsidian.picker.pick(items, { prompt_title = "Resolve link" }) -- calls open_qf_entry by default
    end
  end)
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
  if api.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  elseif api.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  elseif has_markdown_folding() and api.cursor_heading() then
    return "za"
  elseif Obsidian.opts.checkbox.enabled and (api.cursor_checkbox() or Obsidian.opts.checkbox.create_new) then
    return legacy and "<cmd>ObsidianToggleCheckbox<cr>" or "<cmd>Obsidian toggle_checkbox<cr>"
  else
    return "<CR>"
  end
end

---Check if we are in node that should not do checkbox operations.
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
---@param cur string|nil
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
---@return string|nil prefix
---@return string|nil rest
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
---@return string|nil state
---@return string|nil ws
---@return string|nil body
local function parse_checkbox_rest(rest)
  local state, ws, body = rest:match "^%[(.)%](%s*)(.*)$"
  if state ~= nil then
    return state, ws, body
  end
  return nil, nil, nil
end

---Toggle the checkbox on a lnum
---
---@param states string[] Optional table containing checkbox states (e.g., {" ", "x"}).
---@param lnum number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M._toggle_checkbox = function(states, lnum)
  if no_checkbox() then
    return
  end
  lnum = lnum or unpack(vim.api.nvim_win_get_cursor(0))
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
---@param start_lnum integer|?
---@param end_lnum integer|?
M.toggle_checkbox = function(start_lnum, end_lnum)
  local viz = api.get_visual_selection { strict = true }
  local states = Obsidian.opts.checkbox.order
  ---@cast states -nil
  if viz then
    start_lnum, end_lnum = viz.csrow, viz.cerow
  else
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

---Set the checkbox on the current line to a specific state.
---
---@param state string|nil Optional string of state to set the checkbox to (e.g., " ", "x").
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
    ---@cast key -string
    state = string.char(key)
  end

  local found = false
  for _, value in ipairs(Obsidian.opts.checkbox.order) do
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
  if prefix then
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
  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { cur_line })
end

--- Calculate the byte position after a UTF-8 character at the given byte position.
--- This is needed because visual selection cecol points to the start byte of the last
--- selected character, but we need the position after the full character.
---
---@param line string The line content
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
---@param viz obsidian.selection The visual selection
---@param new_text string The replacement text
---@param bufnr integer? Buffer number (defaults to current buffer)
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
---@param viz obsidian.selection
---@param new_text string
---@param opts { apply: boolean? }? Options. apply defaults to true.
---@return lsp.TextDocumentEdit|?
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

  Obsidian.picker.find_notes {
    prompt_title = "Select note to link",
    query = query,
    callback = function(path)
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

---Extract the selected text into a new note
---and replace the selection with a link to the new note.
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
  local note = require("obsidian.note").create {
    id = label,
    template = Obsidian.opts.note.template,
    should_write = true,
  }

  -- replace selection with link to new note
  local link = note:format_link()
  replace_selection(viz, link)

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"

  -- add the selected text to the end of the new note
  note:open { sync = true }
  vim.api.nvim_buf_set_lines(0, -1, -1, false, content)
end

---@param id string|?
---@param callback fun(note: obsidian.Note)|?
M.new = function(id, callback)
  if not id then
    id = api.input("Enter id or path (optional): ", { completion = "file" })
    if not id then
      return log.warn "Aborted"
    elseif id == "" then
      id = nil
    end
  end

  local note = Note.create {
    id = id,
    template = Obsidian.opts.note.template, -- TODO: maybe unneed when creating, or set as a field that note carries
    should_write = true,
  }

  if callback then
    callback(note)
  else
    note:open { sync = true }
  end
end

---@param id string|?
---@param template string|?
---@param callback fun(note: obsidian.Note)|?
M.new_from_template = function(id, template, callback)
  local templates_dir = api.templates_dir()
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end

  if id ~= nil and template ~= nil then
    local note = Note.create {
      id = id,
      template = template,
      should_write = true,
    }
    if callback then
      callback(note)
    else
      note:open { sync = true }
    end
    return
  end

  Obsidian.picker.find_files {
    prompt_title = "Templates",
    dir = templates_dir,
    no_default_mappings = true,
    callback = function(template_name)
      if id == nil or id == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(util.input, "Enter title or path (optional): ", { completion = "file" })
        id = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          return
        elseif safe_title == "" then
          id = nil
        end
      end

      if template_name == nil or template_name == "" then
        log.warn "Aborted"
        return
      end

      ---@type obsidian.Note
      local note = Note.create { id = id, template = template_name, should_write = true }

      if callback then
        callback(note)
      else
        note:open { sync = false } -- TODO:??
      end
    end,
  }
end

-- https://help.obsidian.md/plugins/unique-note
---@param timestamp integer|?
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
---@param timestamp integer|?
---@return string?
M.unique_link = function(timestamp)
  local link = require("obsidian.unique").new_unique_link(timestamp)
  if not link then
    return
  end
  vim.api.nvim_put({ link }, "c", true, true)
  return link
end

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

M.start_presentation = function(buf)
  local note = Note.from_buffer(buf)
  require("obsidian.slides").start_presentation(note)
end

---@param opts? { output_type: "md"|"qf"|string|? }
---@return "md"|"qf"
local function normalize_output_type(opts)
  opts = opts or {}
  local output_type = opts.output_type or "md"
  if output_type ~= "md" and output_type ~= "qf" then
    log.err("Invalid output_type '%s', expected 'md' or 'qf'", tostring(output_type))
    return "md"
  end
  return output_type
end

---@return obsidian.Note[]
local function collect_workspace_notes()
  ---@type obsidian.Note[]
  local notes = {}
  for path in api.dir(Obsidian.dir) do
    local ok, note = pcall(Note.from_file, path)
    if ok and note then
      notes[#notes + 1] = note
    end
  end
  return notes
end

---@param title string
---@param filename string
---@param lines string[]
local function open_markdown_report(title, filename, lines)
  local path = Obsidian.dir / filename
  util.write_file(tostring(path), table.concat(lines, "\n") .. "\n")
  api.open_note({
    filename = tostring(path),
    lnum = 1,
    col = 1,
  }, "e")
  log.info("Wrote %s to '%s'", title, tostring(path:vault_relative_path { strict = true }))
end

---@param title string
---@param items vim.quickfix.entry[]
local function open_quickfix_report(title, items)
  if vim.tbl_isempty(items) then
    return log.info("No results for %s", title)
  end
  vim.fn.setqflist({}, " ", { title = title, items = items })
  vim.cmd "copen"
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

---@param location string
---@return string[]
local function path_location_candidates(location)
  local candidates = {
    location,
    location:gsub("^%./", ""),
    location:gsub("^/", ""),
    vim.uri_decode(location),
  }

  local dedup = {}
  local out = {}
  for _, candidate in ipairs(candidates) do
    if candidate and candidate ~= "" and not dedup[candidate] then
      dedup[candidate] = true
      out[#out + 1] = candidate
    end
  end
  return out
end

---@param notes obsidian.Note[]
---@return table<string, string>
---@return table<string, string>
local function build_note_lookups(notes)
  local reference_lookup = {}
  local absolute_lookup = {}

  for _, note in ipairs(notes) do
    local abs = tostring(note.path:resolve())
    local abs_key = abs:lower()
    absolute_lookup[abs_key] = abs
    reference_lookup[abs_key] = abs

    for _, ref in ipairs(note:get_reference_paths { urlencode = true }) do
      local key = ref:lower()
      if not reference_lookup[key] then
        reference_lookup[key] = abs
      end
    end

    for _, alias in ipairs(note.aliases) do
      local key = alias:lower()
      if not reference_lookup[key] then
        reference_lookup[key] = abs
      end
    end
  end

  return reference_lookup, absolute_lookup
end

---@param source_path obsidian.Path
---@param location string
---@param reference_lookup table<string, string>
---@param absolute_lookup table<string, string>
---@return string|nil
local function resolve_target_path(source_path, location, reference_lookup, absolute_lookup)
  for _, candidate in ipairs(path_location_candidates(location)) do
    local reference_hit = reference_lookup[candidate:lower()]
    if reference_hit then
      return reference_hit
    end

    local parent = source_path:parent()
    if parent ~= nil then
      local resolved = tostring((parent / candidate):resolve())
      local absolute_hit = absolute_lookup[resolved:lower()]
      if absolute_hit then
        return absolute_hit
      end
    end
  end

  return nil
end


---@param opts? { output_type: "md"|"qf"|string|? }
M.list_empty_files = function(opts)
  -- TODO: expand scan scope to include non-note filetypes.
  local output_type = normalize_output_type(opts)
  local notes = collect_workspace_notes()

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

  if output_type == "qf" then
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
    return open_quickfix_report("Obsidian Empty Files", items)
  end

  local lines = { "# Empty files", "" }
  for _, note in ipairs(empty_notes) do
    local rel = tostring(assert(note.path:vault_relative_path { strict = true }))
    lines[#lines + 1] = "- [[" .. rel .. "]]"
  end
  if #empty_notes == 0 then
    lines[#lines + 1] = "No empty files found."
  end

  open_markdown_report("Obsidian Empty Files", "empty files result.md", lines)
end

---@param opts? { output_type: "md"|"qf"|string|? }
M.list_orphan_files = function(opts)
  -- TODO: expand scan scope to include non-note filetypes.
  local output_type = normalize_output_type(opts)
  local notes = collect_workspace_notes()
  local reference_lookup, absolute_lookup = build_note_lookups(notes)

  ---@type table<string, integer>
  local inbound = {}
  for _, note in ipairs(notes) do
    inbound[tostring(note.path:resolve())] = 0
  end

  for _, source_note in ipairs(notes) do
    for _, match in ipairs(source_note:links { dedup = false }) do
      local location, _, link_type = util.parse_link(match.link, { strip = true })
      if
        location
        and location ~= ""
        and link_type ~= "HeaderLink"
        and link_type ~= "BlockLink"
        and not util.is_uri(location)
      then
        local target_path = resolve_target_path(source_note.path, location, reference_lookup, absolute_lookup)
        if target_path ~= nil and inbound[target_path] ~= nil then
          inbound[target_path] = inbound[target_path] + 1
        end
      end
    end
  end

  ---@type obsidian.Note[]
  local orphan_notes = {}
  for _, note in ipairs(notes) do
    local path = tostring(note.path:resolve())
    if inbound[path] == 0 then
      orphan_notes[#orphan_notes + 1] = note
    end
  end

  table.sort(orphan_notes, function(a, b)
    return tostring(a.path) < tostring(b.path)
  end)

  if output_type == "qf" then
    ---@type vim.quickfix.entry[]
    local items = {}
    for _, note in ipairs(orphan_notes) do
      items[#items + 1] = {
        filename = tostring(note.path),
        lnum = 1,
        col = 1,
        text = "Orphan file",
      }
    end
    return open_quickfix_report("Obsidian Orphan Files", items)
  end

  local lines = { "# Orphan files", "" }
  for _, note in ipairs(orphan_notes) do
    local rel = tostring(assert(note.path:vault_relative_path { strict = true }))
    lines[#lines + 1] = "- [[" .. rel .. "]]"
  end
  if #orphan_notes == 0 then
    lines[#lines + 1] = "No orphan files found."
  end

  open_markdown_report("Obsidian Orphan Files", "orphan files result.md", lines)
end

---@param opts? { output_type: "md"|"qf"|string|? }
M.list_dead_links = function(opts)
  -- TODO: expand scan scope to include non-note filetypes.
  local output_type = normalize_output_type(opts)
  local entries = dead_links_analysis.collect { use_cache = false }

  ---@type vim.quickfix.entry[]
  local items = {}

  for _, entry in ipairs(entries) do
    items[#items + 1] = {
      filename = entry.filename,
      lnum = entry.line,
      col = entry.start + 1,
      text = entry.text,
    }
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

  if output_type == "qf" then
    return open_quickfix_report("Obsidian Dead Links", items)
  end

  local md_lines = { "# Dead links", "" }
  for _, item in ipairs(items) do
    local rel = tostring(assert(Path.new(item.filename):vault_relative_path { strict = true }))
    md_lines[#md_lines + 1] = string.format("- [[%s]]:%d:%d - %s", rel, item.lnum, item.col, item.text)
  end
  if vim.tbl_isempty(items) then
    md_lines[#md_lines + 1] = "No dead links found."
  end

  open_markdown_report("Obsidian Dead Links", "dead links result.md", md_lines)
end

return M
