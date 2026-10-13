local resolvers = require "obsidian.resolvers"

local M = {}

--- A note to resolve completion documentation for.
---
---@class obsidian.completion.docs.Entry
---@field note obsidian.Note
---@field label string|?
---@field anchor obsidian.note.HeaderAnchor|?
---@field block obsidian.note.Block|?

--- Resolve completion documentation for notes through the `note_preview` resolver.
---
--- Results are index-aligned with `entries`. When a custom resolver cancels or fails,
--- the built-in rendering is used so documentation never disappears.
---
---@param entries obsidian.completion.docs.Entry[]
---@param done fun(values: string[]) Markdown documentation strings.
M.resolve_all = function(entries, done)
  local values = {}
  local pending = #entries

  if pending == 0 then
    done(values)
    return
  end

  for i, entry in ipairs(entries) do
    ---@type obsidian.resolver.NotePreviewCtx
    local ctx = {
      scope = "lsp.completion",
      note = entry.note,
      label = entry.label,
      anchor = entry.anchor,
      block = entry.block,
    }
    resolvers.resolve("note_preview", ctx, function(result)
      values[i] = type(result) == "string" and result or resolvers.default_note_preview(ctx)
      pending = pending - 1
      if pending == 0 then
        done(values)
      end
    end)
  end
end

return M
