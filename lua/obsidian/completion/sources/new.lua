local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local Note = require "obsidian.note"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, search, insert_start, insert_end = completion.can_complete(request)

  if (not can_complete) or (#search >= Obsidian.opts.completion.min_chars) then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast search -nil
  ---@cast insert_start -nil
  ---@cast insert_end -nil

  search = util.lstrip_whitespace(search)

  ---@type string|?
  local block_link
  search, block_link = util.strip_block_links(search)

  ---@type string|?
  local anchor_link
  search, anchor_link = util.strip_anchor_links(search)

  -- If block link is incomplete, do nothing.
  if not block_link and vim.endswith(search, "#^") then
    callback(EMPTY_RESPONSE)
    return
  end

  -- If anchor link is incomplete, do nothing.
  if not anchor_link and vim.endswith(search, "#") then
    callback(EMPTY_RESPONSE)
    return
  end

  -- Probably just a block/anchor link within current note.
  if string.len(search) == 0 then
    callback(EMPTY_RESPONSE)
    return
  end

  -- Create a mock block.
  ---@type obsidian.note.Block|?
  local block
  if block_link then
    block = { block = "", id = util.standardize_block(block_link), line = 1 }
  end

  -- Create a mock anchor.
  ---@type obsidian.note.HeaderAnchor|?
  local anchor
  if anchor_link then
    anchor = { anchor = anchor_link, header = string.sub(anchor_link, 2), level = 1, line = 1 }
  end

  ---@type { label: string, note: obsidian.Note, template: string|? }[]
  local new_notes_opts = {}

  local note = Note.create { id = search, template = Obsidian.opts.note.template }
  if note.id and string.len(note.id) > 0 then
    new_notes_opts[#new_notes_opts + 1] = { label = search, note = note }
  end

  -- Check for datetime macros.
  for _, dt_offset in ipairs(util.resolve_date_macro(search)) do
    if dt_offset.cadence == "daily" then
      note = require("obsidian.daily").daily { offset = dt_offset.offset, no_write = true }
      if not note:exists() then
        new_notes_opts[#new_notes_opts + 1] =
          { label = dt_offset.macro, note = note, template = Obsidian.opts.daily_notes.template }
      end
    end
  end

  -- Completion items.
  local items = {}

  for _, new_note_opts in ipairs(new_notes_opts) do
    local new_note = new_note_opts.note

    assert(new_note.path, "note without path")

    local label
    if Obsidian.opts.link.style == "wiki" then
      label = string.format("[[%s]] (create)", new_note_opts.label)
    elseif Obsidian.opts.link.style == "markdown" then
      label = string.format("[%s](…) (create)", new_note_opts.label)
    elseif type(Obsidian.opts.link.style) == "function" then
      label = Obsidian.opts.link.style { label = new_note_opts.label, path = "…" } .. " (create)"
    else
      error "not implemented"
    end

    local new_text = new_note:format_link {
      label = new_note_opts.label,
      anchor = anchor,
      block = block,
    }
    local documentation = {
      kind = "markdown",
      value = new_note:display_info {
        label = "Create: " .. new_text,
      },
    }

    ---@type lsp.Range
    local range = {
      start = {
        line = request.line,
        character = insert_start,
      },
      ["end"] = {
        line = request.line,
        character = insert_end + 1,
      },
    }

    ---@type lsp.CompletionItem
    local item = {
      documentation = documentation,
      sortText = new_note_opts.label,
      filterText = completion.get_filter_text(new_note_opts.label),
      label = label,
      kind = vim.lsp.protocol.CompletionItemKind.Reference,
      command = {
        command = "obsidian.new",
        title = "Obsidian new",
        arguments = { new_note.id, new_note_opts.template },
      },
      -- NOTE: for [[new_note@template future expansion
      -- command = {
      --   command = "obsidian.new_from_template",
      --   title = "Obsidian new_from_template",
      --   arguments = { new_note.id, new_note_opts.template } --
      -- },
      textEdit = {
        newText = new_text,
        range = range,
      },
    }

    items[#items + 1] = item
  end

  callback {
    isIncomplete = true,
    items = items,
  }
end

return M
