--- A minimal imitation of the experimental `vim.range` API (neovim/neovim#25509).
---
--- Only the useful subset is implemented here. Field names and semantics match
--- `vim.Range` (0-based rows/cols, end-exclusive), so that once `vim.range`
--- stabilizes, migrating is mechanical:
--- `vim.range(buf, r.start_row, r.start_col, r.end_row, r.end_col)`.
---
--- Unlike `vim.Range`, no buffer handle is carried: ranges here typically
--- describe locations in note *files* that may not be loaded in a buffer.
---
--- NOTE: prefer calling these as module functions (`Range.to_lsp(r)`) rather
--- than methods (`r:to_lsp()`) inside the plugin, because ranges that
--- round-trip through `vim.b` (see `Note.from_buffer`) lose their metatable.

--- Represents a range in a file or buffer. 0-based, end-exclusive.
---
---@class obsidian.Range
---@field start_row integer 0-based start row.
---@field start_col integer 0-based start col, byte index.
---@field end_row integer 0-based end row.
---@field end_col integer 0-based end col, byte index, exclusive.
local Range = {}
Range.__index = Range

---@param start_row integer
---@param start_col integer
---@param end_row integer
---@param end_col integer
---@return obsidian.Range
Range.new = function(start_row, start_col, end_row, end_col)
  return setmetatable({
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col,
  }, Range)
end

--- Checks whether the given range is empty; i.e., start >= end.
---
---@param range obsidian.Range
---@return boolean
Range.is_empty = function(range)
  return range.start_row > range.end_row or (range.start_row == range.end_row and range.start_col >= range.end_col)
end

--- Converts an |obsidian.Range| to an `lsp.Range`.
---
--- NOTE: `lsp.Position.character` is measured in code units of the position
--- encoding while ours is a byte index. The ranges produced by this plugin are
--- line-based (cols are always 0), where the two are identical, so no buffer
--- access or re-encoding is needed.
---
---@param range obsidian.Range
---@return lsp.Range
Range.to_lsp = function(range)
  return {
    start = { line = range.start_row, character = range.start_col },
    ["end"] = { line = range.end_row, character = range.end_col },
  }
end

--- Creates a new |obsidian.Range| from an `lsp.Range`.
---
---@param range lsp.Range
---@return obsidian.Range
Range.lsp = function(range)
  return Range.new(range.start.line, range.start.character, range["end"].line, range["end"].character)
end

setmetatable(Range, {
  __call = function(_, ...)
    return Range.new(...)
  end,
})

return Range
