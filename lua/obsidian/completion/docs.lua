local log = require "obsidian.log"
local resolvers = require "obsidian.resolvers"

local M = {}

--- A note preview context registered for lazy documentation resolution.
---
---@class obsidian.completion.docs.Entry
---@field note obsidian.Note
---@field label string|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?

--- A registered preview context and the completion request it belongs to.
---
---@class obsidian.completion.docs.Record
---@field entry obsidian.completion.docs.Entry
---@field generation integer

--- Registered preview contexts, keyed by an opaque id that is round-tripped
--- through `CompletionItem.data` by completion clients.
---@type table<integer, obsidian.completion.docs.Record>
local contexts = {}

--- Registration order of keys, for FIFO eviction.
---@type integer[]
local order = {}

local next_key = 0
local generation = 0

--- Soft cap. When exceeded, entries from previous completion requests are
--- evicted first (oldest first) so a large response can never evict its own
--- entries; a single response may exceed this until the next request arrives.
local MAX_CONTEXTS = 1024

--- Absolute cap, bounding flows that never advance the generation.
local HARD_MAX_CONTEXTS = 4 * MAX_CONTEXTS

local function evict_stale()
  -- Drop entries from previous generations first, oldest first.
  local i = 1
  while #order > MAX_CONTEXTS and i <= #order do
    local key = order[i]
    if contexts[key].generation < generation then
      contexts[key] = nil
      table.remove(order, i)
    else
      i = i + 1
    end
  end
  -- Hard cap for flows that never advance the generation.
  while #order > HARD_MAX_CONTEXTS do
    contexts[table.remove(order, 1)] = nil
  end
end

--- Mark the start of a new completion request.
---
--- Entries registered for previous requests become evictable, while entries of
--- the current one are protected until the next request arrives.
M.begin_request = function()
  generation = generation + 1
end

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
  contexts[key] = { entry = entry, generation = generation }
  order[#order + 1] = key

  if #order > MAX_CONTEXTS then
    evict_stale()
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
  local key = type(item.data) == "table" and item.data.obsidian_note_preview or nil
  local record = key and contexts[key] or nil
  ---@cast record obsidian.completion.docs.Record|?
  if record == nil then
    done(item)
    return
  end

  ---@type obsidian.resolver.NotePreviewCtx
  local ctx = {
    scope = "lsp.completion",
    note = record.entry.note,
    label = record.entry.label,
    anchor = record.entry.anchor,
    block = record.entry.block,
  }
  resolvers.resolve("note_preview", ctx, function(result)
    if type(result) ~= "string" then
      log.warn "note_preview resolver returned a non-string result, using the default rendering"
    end
    item.documentation = {
      kind = "markdown",
      value = type(result) == "string" and result or resolvers.default_note_preview(ctx),
    }
    done(item)
  end)
end

return M
