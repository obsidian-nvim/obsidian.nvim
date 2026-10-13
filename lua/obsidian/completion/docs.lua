local resolvers = require "obsidian.resolvers"

local M = {}

--- A note preview context registered for lazy documentation resolution.
---
---@class obsidian.completion.docs.Entry
---@field note obsidian.Note
---@field label string|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?

--- Registered preview contexts, keyed by an opaque id that is round-tripped
--- through `CompletionItem.data` by completion clients. Bounded so repeated
--- completion requests cannot grow it indefinitely; entries are dropped
--- FIFO once the cap is exceeded.
---@type table<integer, obsidian.completion.docs.Entry>
local contexts = {}
local order = {}
local next_key = 0
local MAX_CONTEXTS = 1024

--- Register a note preview context for a completion item.
---
--- Returns the value to assign to the item's `data` field. Documentation is
--- resolved later, per item, when the client sends `completionItem/resolve`.
---
---@param entry obsidian.completion.docs.Entry
---@return table data
M.register = function(entry)
  next_key = next_key + 1
  local key = next_key
  contexts[key] = entry
  order[#order + 1] = key
  while #order > MAX_CONTEXTS do
    contexts[table.remove(order, 1)] = nil
  end
  return { obsidian_note_preview = key }
end

--- Resolve documentation for a completion item through the `note_preview` resolver.
---
--- Items registered by `M.register` get their documentation filled in; all other
--- items are passed through unchanged. When a custom resolver cancels or fails,
--- the built-in rendering is used so documentation never disappears.
---
---@param item lsp.CompletionItem
---@param done fun(item: lsp.CompletionItem)
M.resolve_item = function(item, done)
  local key = item.data and item.data.obsidian_note_preview
  local entry = key and contexts[key] or nil
  ---@cast entry obsidian.completion.docs.Entry|?
  if entry == nil then
    done(item)
    return
  end

  ---@type obsidian.resolver.NotePreviewCtx
  local ctx = {
    scope = "lsp.completion",
    note = entry.note,
    label = entry.label,
    anchor = entry.anchor,
    block = entry.block,
  }
  resolvers.resolve("note_preview", ctx, function(result)
    item.documentation = {
      kind = "markdown",
      value = type(result) == "string" and result or resolvers.default_note_preview(ctx),
    }
    done(item)
  end)
end

return M
