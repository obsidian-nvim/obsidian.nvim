local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local Note = require "obsidian.note"
local api = require "obsidian.api"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

--- Build the note needed to render a completion item without actually creating it.
--- In particular, this must not fire note creation callbacks or prompt while the
--- user is still typing. Invalid intermediate filenames simply produce no item.
---@param opts obsidian.note.NoteOpts
---@return obsidian.Note|?
local function preview_note(opts)
  ---@diagnostic disable-next-line: access-invisible
  local ok, id, path, title = pcall(Note._resolve_id_path, opts, false)
  if not ok then
    return nil
  end

  local note = Note.new(id, opts.aliases, opts.tags, path, title)
  note.template = opts.template
  return note
end

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, term, insert_start, insert_end = completion.can_complete(request)

  if not can_complete or term == nil then
    callback(EMPTY_RESPONSE)
    return
  end

  if completion.block_search(term) ~= nil or #term < Obsidian.opts.completion.min_chars then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast term -nil
  ---@cast insert_start -nil
  ---@cast insert_end -nil

  term = util.lstrip_whitespace(term)

  ---@type string|?
  local block_link
  term, block_link = util.strip_block_links(term)

  ---@type string|?
  local anchor_link
  term, anchor_link = util.strip_anchor_links(term)

  -- If block link is incomplete, do nothing.
  if not block_link and vim.endswith(term, "#^") then
    callback(EMPTY_RESPONSE)
    return
  end

  -- If anchor link is incomplete, do nothing.
  if not anchor_link and vim.endswith(term, "#") then
    callback(EMPTY_RESPONSE)
    return
  end

  -- Probably just a block/anchor link within current note.
  if string.len(term) == 0 then
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

  ---@type { label: string, note: obsidian.Note, scope: string }[]
  local new_notes_opts = {}

  local source_path = vim.api.nvim_buf_get_name(request.bufnr)
  local workspace_dir = api.resolve_workspace_dir(source_path)
  local note = preview_note { id = term, template = Obsidian.opts.note.template, source_path = source_path }
  if note and note.id and string.len(note.id) > 0 then
    new_notes_opts[#new_notes_opts + 1] = { label = term, note = note, scope = "plain" }
  end

  -- Check for datetime macros. Build missing daily notes directly instead of
  -- calling daily(), which would call Note.create for every completion request.
  for _, dt_offset in ipairs(util.resolve_date_macro(term)) do
    if dt_offset.cadence == "daily" then
      local daily = require "obsidian.daily"
      local timestamp = os.time() + (dt_offset.offset * 3600 * 24)
      local path, id = daily.daily_note_path(timestamp, workspace_dir)
      local aliases = {}
      if Obsidian.opts.daily_notes.alias_format ~= nil then
        aliases[1] = tostring(util.format_date(timestamp, Obsidian.opts.daily_notes.alias_format))
      end
      note = preview_note {
        id = id,
        verbatim = true,
        aliases = aliases,
        tags = Obsidian.opts.daily_notes.default_tags or {},
        dir = path:parent(),
        template = Obsidian.opts.daily_notes.template,
        source_path = source_path,
        scope = "daily",
      }
      if note and not note:exists() then
        new_notes_opts[#new_notes_opts + 1] = { label = dt_offset.macro, note = note, scope = "daily" }
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
      dir = source_path ~= "" and vim.fs.dirname(source_path) or nil,
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
        arguments = { new_note, new_note_opts.scope },
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
