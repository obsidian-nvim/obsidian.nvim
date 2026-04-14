local completion = require "obsidian.completion.refs"
local util = require "obsidian.util"
local Note = require "obsidian.note"

---Used to track variables that are used between reusable method calls. This is required, because each
---call to the sources's completion hook won't create a new source object, but will reuse the same one.
---@class obsidian.completion.NewNoteSourceCompletionContext
---@field completion_resolve_callback fun(resp: lsp.CompletionList)
---@field request obsidian.completion.Request
---@field search string|?
---@field insert_start integer|?
---@field insert_end integer|?

local M = {}

--- Returns whatever it's possible to complete the search and sets up the search related variables in cc
---@param cc obsidian.completion.NewNoteSourceCompletionContext
---@return boolean success provides a chance to return early if the request didn't meet the requirements
local function can_complete_request(cc)
  local can_complete
  can_complete, cc.search, cc.insert_start, cc.insert_end = completion.can_complete(cc.request)

  if cc.search ~= nil then
    cc.search = util.lstrip_whitespace(cc.search)
  end

  if not (can_complete and cc.search ~= nil and #cc.search >= Obsidian.opts.completion.min_chars) then
    return false
  end
  return true
end

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param completion_resolve_callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(completion_resolve_callback, request)
  local cc = {
    completion_resolve_callback = completion_resolve_callback,
    request = request,
  }
  if not can_complete_request(cc) then
    cc.completion_resolve_callback(M.incomplete_response)
    return
  end

  ---@type string|?
  local block_link
  cc.search, block_link = util.strip_block_links(cc.search)

  ---@type string|?
  local anchor_link
  cc.search, anchor_link = util.strip_anchor_links(cc.search)

  -- If block link is incomplete, do nothing.
  if not block_link and vim.endswith(cc.search, "#^") then
    cc.completion_resolve_callback(M.incomplete_response)
    return
  end

  -- If anchor link is incomplete, do nothing.
  if not anchor_link and vim.endswith(cc.search, "#") then
    cc.completion_resolve_callback(M.incomplete_response)
    return
  end

  -- Probably just a block/anchor link within current note.
  if string.len(cc.search) == 0 then
    cc.completion_resolve_callback(M.incomplete_response)
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

  local note = Note.create { id = cc.search, template = Obsidian.opts.note.template }
  if note.id and string.len(note.id) > 0 then
    new_notes_opts[#new_notes_opts + 1] = { label = cc.search, note = note }
  end

  -- Check for datetime macros.
  for _, dt_offset in ipairs(util.resolve_date_macro(cc.search)) do
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

    ---@cast cc.insert_end -nil
    ---@cast cc.insert_start -nil

    ---@type lsp.Range
    local range = {
      start = {
        line = cc.request.line,
        character = cc.insert_start,
      },
      ["end"] = {
        line = cc.request.line,
        character = cc.insert_end + 1,
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
      -- command = {
      --   command = "obsidian.new_from_template",
      --   title = "Obsidian new_from_template",
      --   arguments = { new_note.id, new_note_opts.template } -- for [[new_note@template future expansion
      -- },
      textEdit = {
        newText = new_text,
        range = range,
      },
    }

    items[#items + 1] = item
  end

  local completion_list = vim.tbl_deep_extend("force", completion.complete_response, { items = items })
  cc.completion_resolve_callback(completion_list)
end

return M
