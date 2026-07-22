local completion = require "obsidian.completion.anchors"
local api = require "obsidian.api"
local search = require "obsidian.search"
local util = require "obsidian.util"

local M = {}

local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---@param context obsidian.completion.FragmentContext
---@param note obsidian.Note
---@param anchor obsidian.note.HeaderAnchor
---@return string
local function format_link(context, note, anchor)
  if context.ref ~= "" then
    return note:format_link { label = context.label or context.ref, anchor = anchor }
  end

  if Obsidian.opts.link.style == "wiki" then
    return "[[#" .. anchor.header .. "]]"
  elseif Obsidian.opts.link.style == "markdown" then
    return "[#" .. anchor.header .. "](" .. anchor.anchor .. ")"
  elseif type(Obsidian.opts.link.style) == "function" then
    return Obsidian.opts.link.style { label = "", path = "", anchor = anchor }
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

  local anchor_query = util.standardize_anchor(context.fragment)
  local function process_notes(notes)
    local items = {}
    local seen = {}

    for _, note in ipairs(notes) do
      for _, anchor in ipairs(completion.collect_matching(note, anchor_query)) do
        local new_text = format_link(context, note, anchor)
        if not seen[new_text] then
          seen[new_text] = true
          items[#items + 1] = {
            label = anchor.anchor .. " — " .. anchor.header,
            sortText = anchor.anchor,
            filterText = context.filter_prefix .. anchor.anchor:sub(#anchor_query + 1),
            kind = vim.lsp.protocol.CompletionItemKind.Reference,
            documentation = {
              kind = "markdown",
              value = context.ref == "" and string.format("`%s`", new_text)
                or note:display_info { label = new_text, anchor = anchor },
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
    local note = api.current_note(request.bufnr, { collect_anchor_links = true })
    if note then
      process_notes { note }
    else
      callback(EMPTY_RESPONSE)
    end
  else
    search.resolve_note_async(context.ref, process_notes, {
      notes = { collect_anchor_links = true },
    })
  end
end

return M
