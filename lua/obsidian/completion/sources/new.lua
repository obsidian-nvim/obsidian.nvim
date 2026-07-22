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
  local can_complete, term, insert_start, insert_end = completion.can_complete(request)

  if (not can_complete) or (#term < Obsidian.opts.completion.min_chars) then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast term -nil
  ---@cast insert_start -nil
  ---@cast insert_end -nil

  term = util.lstrip_whitespace(term)

  ---@type { label: string, note: obsidian.Note }[]
  local new_notes_opts = {}

  local note = Note.create { id = term, template = Obsidian.opts.note.template }
  if note.id and string.len(note.id) > 0 then
    new_notes_opts[#new_notes_opts + 1] = { label = term, note = note }
  end

  -- Check for datetime macros.
  for _, dt_offset in ipairs(util.resolve_date_macro(term)) do
    if dt_offset.cadence == "daily" then
      note = require("obsidian.daily").daily { offset = dt_offset.offset }
      if not note:exists() then
        new_notes_opts[#new_notes_opts + 1] = { label = dt_offset.macro, note = note }
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

    local new_text = new_note:format_link { label = new_note_opts.label }
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
        character = insert_end,
      },
    }

    ---@cast new_note table new_note metatable gets lost anyway

    ---@type lsp.CompletionItem
    local item = {
      documentation = documentation,
      sortText = new_note_opts.label,
      filterText = completion.get_filter_text(new_note_opts.label),
      label = label,
      kind = vim.lsp.protocol.CompletionItemKind.Reference,
      command = {
        command = "obsidian.write_note",
        title = "Obsidian write note",
        arguments = { new_note },
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
