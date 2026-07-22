local completion = require "obsidian.completion.blocks"
local api = require "obsidian.api"
local search = require "obsidian.search"

local M = {}

local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@param context obsidian.completion.FragmentContext
---@param note obsidian.Note
---@param block obsidian.note.Block
---@return string
local function format_link(context, note, block)
  if context.ref ~= "" then
    return note:format_link { label = context.label or context.ref, block = block }
  end

  if Obsidian.opts.link.style == "wiki" then
    return "[[#" .. block.id .. "]]"
  elseif Obsidian.opts.link.style == "markdown" then
    return "[#" .. block.id .. "](#" .. block.id .. ")"
  elseif type(Obsidian.opts.link.style) == "function" then
    return Obsidian.opts.link.style { label = "", path = "", block = block }
  else
    error "not implemented"
  end
end

---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, context = completion.can_complete(request)
  if not can_complete or not context then
    callback(EMPTY_RESPONSE)
    return
  end

  local function process_notes(notes)
    local items = {}
    local seen = {}

    for _, note in ipairs(notes) do
      for _, block in ipairs(completion.collect_matching(note, context.fragment)) do
        local new_text = format_link(context, note, block)
        if not seen[new_text] then
          seen[new_text] = true
          items[#items + 1] = {
            label = "#" .. block.id,
            sortText = block.id,
            filterText = context.filter_prefix .. ("#" .. block.id):sub(#context.fragment + 1),
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            documentation = {
              kind = "markdown",
              value = context.ref == "" and string.format("`%s`", new_text)
                or note:display_info { label = new_text, block = block },
            },
            textEdit = {
              newText = new_text,
              range = {
                start = { line = request.line, character = context.insert_start },
                ["end"] = { line = request.line, character = context.insert_end },
              },
            },
          }
        end
      end
    end

    callback { isIncomplete = true, items = items }
  end

  if context.ref == "" then
    local note = api.current_note(request.bufnr, { collect_blocks = true })
    if note then
      process_notes { note }
    else
      callback(EMPTY_RESPONSE)
    end
  else
    search.resolve_note_async(context.ref, process_notes, {
      notes = { collect_blocks = true },
    })
  end
end

return M
