local completion = require "obsidian.completion.footnotes"
local footnotes = require "obsidian.footnotes"

local M = {}

---@type lsp.CompletionList
local EMPTY_RESPONSE = {
  isIncomplete = true,
  items = {},
}

---The next free numeric footnote id, e.g. "2" when "[^1]" already exists.
---@param defs obsidian.footnote.Definition[]
---@return string
local function next_numeric_id(defs)
  local max = 0
  for _, def in ipairs(defs) do
    local n = tonumber(def.id)
    if n and n > max then
      ---@cast n integer
      max = n
    end
  end
  return tostring(max + 1)
end

local MAX_LABEL_LENGTH = 80

---Sort the new footnote item first, then numeric ids in numeric order, then the rest.
---@param id string
---@return string
local function sort_text(id)
  local n = tonumber(id)
  if n then
    return ("1%09d"):format(n)
  end
  return "2" .. id
end

---@param label string
---@return string
local function truncate_label(label)
  if vim.fn.strchars(label) <= MAX_LABEL_LENGTH then
    return label
  end
  return vim.fn.strcharpart(label, 0, MAX_LABEL_LENGTH - 1) .. "…"
end

---@param id string
---@param text string
---@return string
local function definition_label(id, text)
  return truncate_label(("[^%s]: %s"):format(id, text))
end

---@param request obsidian.completion.Request
---@param insert_start integer
---@param ref string
---@return [integer, integer]
local function cursor_after_ref(request, insert_start, ref)
  return { request.line + 1, insert_start + string.len(ref) - 1 }
end

--- Runs a generalized version of the complete (nvim_cmp) or get_completions (blink) methods
---@param callback fun(resp: lsp.CompletionList)
---@param request obsidian.completion.Request
function M.process_completion(callback, request)
  local can_complete, term, insert_start, insert_end = completion.can_complete(request)

  if not can_complete then
    callback(EMPTY_RESPONSE)
    return
  end

  ---@cast term -nil
  ---@cast insert_start -nil
  ---@cast insert_end -nil

  ---@type lsp.Range
  local range = {
    start = { line = request.line, character = insert_start },
    ["end"] = { line = request.line, character = insert_end },
  }

  local defs = footnotes.definitions(request.bufnr)

  ---@type lsp.CompletionItem[]
  local items = {}
  local resolved = false

  -- New numbered footnote first, e.g. "[^2]: New footnote" when "[^1]" exists.
  local new_id = next_numeric_id(defs)
  local new_ref = ("[^%s]"):format(new_id)

  items[#items + 1] = {
    label = ("%s: New footnote"):format(new_ref),
    sortText = "0",
    filterText = new_ref,
    kind = vim.lsp.protocol.CompletionItemKind.Reference,
    textEdit = {
      newText = new_ref,
      range = range,
    },
    command = {
      command = "obsidian.footnote_new",
      title = "Obsidian create footnote",
      arguments = { new_id, request.bufnr, cursor_after_ref(request, insert_start, new_ref) },
    },
  }

  -- Existing footnotes.
  for _, def in ipairs(defs) do
    if def.id == term then
      resolved = true
    end

    local new_text = ("[^%s]"):format(def.id)

    items[#items + 1] = {
      label = definition_label(def.id, def.text),
      sortText = sort_text(def.id),
      filterText = new_text,
      kind = vim.lsp.protocol.CompletionItemKind.Reference,
      textEdit = {
        newText = new_text,
        range = range,
      },
    }
  end

  -- Offer to create the footnote when the typed id doesn't resolve.
  if #term > 0 and not resolved and term ~= new_id then
    local new_text = ("[^%s]"):format(term)

    items[#items + 1] = {
      label = ("%s (create)"):format(new_text),
      sortText = sort_text(term),
      filterText = new_text,
      kind = vim.lsp.protocol.CompletionItemKind.Reference,
      textEdit = {
        newText = new_text,
        range = range,
      },
      command = {
        command = "obsidian.footnote_new",
        title = "Obsidian create footnote",
        arguments = { term, request.bufnr, cursor_after_ref(request, insert_start, new_text) },
      },
    }
  end

  callback {
    isIncomplete = true,
    items = items,
  }
end

return M
