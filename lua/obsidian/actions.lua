--- All the actions you can map

local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1
local M = {}
local log = require "obsidian.log"
local util = require "obsidian.util"

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

--- Create an LSP TextEdit from a visual selection.
--- The edit uses UTF-8 byte offsets (matching our LSP server's offset_encoding).
---
---@param viz obsidian.selection The visual selection
---@param new_text string The replacement text
---@param bufnr integer? Buffer number (defaults to current buffer)
---@return lsp.TextDocumentEdit
local function make_text_edit(viz, new_text, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_buf_get_lines(bufnr, viz.cerow - 1, viz.cerow, false)[1]

  -- Calculate the exclusive end position (byte after the last selected character)
  local end_col = get_utf8_char_end(line, viz.cecol)

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
---@return lsp.TextDocumentEdit
local function replace_selection(viz, new_text, opts)
  opts = opts or {}
  local apply = opts.apply ~= false -- default to true

  local text_edit = make_text_edit(viz, new_text)

  if apply then
    vim.lsp.util.apply_workspace_edit({ documentChanges = { text_edit } }, "utf-8")
    require("obsidian.ui").update(0)
  end

  return text_edit
end

M.link = function()
  local viz = M.get_visual_selection()
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
      replace_selection(viz, note:format_link { label = viz.selection })
    end,
  }
end

---@param label string?
M.link_new = function(label)
  local viz = M.get_visual_selection()
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

  local note = require("obsidian.note").create { title = label }
  replace_selection(viz, note:format_link { label = label })

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"
end

---Extract the selected text into a new note
---and replace the selection with a link to the new note.
---@param label string?
M.extract_note = function(label)
  local viz = M.get_visual_selection()
  if not viz then
    log.err "`Obsidian extract_note` must be called in visual mode"
    return
  end

  local content = vim.split(viz.selection, "\n", { plain = true })

  ---@type string|?
  if label ~= nil and string.len(label) > 0 then
    label = vim.trim(label)
  else
    label = M.input "Enter title (optional): "
    if not label then
      log.warn "Aborted"
      return
    elseif label == "" then
      label = nil
    end
  end

  -- create the new note.
  local note = require("obsidian.note").create { title = label }

  -- replace selection with link to new note
  local link = note:format_link()
  replace_selection(viz, link)

  -- Save file so backlinks search (ripgrep) can find the new link
  vim.cmd "silent! write"

  -- add the selected text to the end of the new note
  note:open { sync = true }
  vim.api.nvim_buf_set_lines(0, -1, -1, false, content)
end

--------------------------
---- Mapping functions ---
--------------------------

---@param direction "next" | "prev"
M.nav_link = function(direction)
  -- vim.validate("direction", direction, "string", false, "nav_link must be called with a direction")
  local cursor_line, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local Note = require "obsidian.note"

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
  if M.cursor_link() then
    return legacy and "<cmd>ObsidianFollowLink<cr>" or "<cmd>Obsidian follow_link<cr>"
  elseif M.cursor_tag() then
    return legacy and "<cmd>ObsidianTags<cr>" or "<cmd>Obsidian tags<cr>"
  elseif has_markdown_folding() and M.cursor_heading() then
    return "za"
  elseif M.cursor_checkbox() or Obsidian.opts.checkbox.create_new then
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

---Toggle the checkbox on the current line.
---
---@param states table|nil Optional table containing checkbox states (e.g., {" ", "x"}).
---@param line_num number|nil Optional line number to toggle the checkbox on. Defaults to the current line.
M.toggle_checkbox = function(states, line_num)
  if no_checkbox() then
    return
  end
  line_num = line_num or unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]

  local checkboxes = states or { " ", "x" }

  if util._is_checkbox(line) then
    for i, check_char in ipairs(checkboxes) do
      if string.match(line, "^.* %[" .. vim.pesc(check_char) .. "%].*") then
        i = i % #checkboxes
        line = string.gsub(line, vim.pesc("[" .. check_char .. "]"), "[" .. checkboxes[i + 1] .. "]", 1)
        break
      end
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(line, unordered_list_pattern) then
      line = string.gsub(line, unordered_list_pattern, "%1- [ ] %2")
    else
      line = string.gsub(line, "^(%s*)", "%1- [ ] ")
    end
  else
    return
  end

  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { line })
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
    state = string.char(key + 0)
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

  if util._is_checkbox(cur_line) then
    if string.match(cur_line, "^.* %[.%].*") then
      cur_line = string.gsub(cur_line, "%[.%]", "[" .. state .. "]", 1)
    end
  elseif Obsidian.opts.checkbox.create_new then
    local unordered_list_pattern = "^(%s*)[-*+] (.*)"
    if string.match(cur_line, unordered_list_pattern) then
      cur_line = string.gsub(cur_line, unordered_list_pattern, "%1- [" .. state .. "] %2")
    else
      cur_line = string.gsub(cur_line, "^(%s*)", "%1- [" .. state .. "] ")
    end
  else
    return
  end

  local line_num = vim.fn.getpos(".")[2]
  vim.api.nvim_buf_set_lines(0, line_num - 1, line_num, true, { cur_line })
end

return M
