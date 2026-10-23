local Path = require "obsidian.path"
local Range = require "obsidian.range"

local M = {}

---@class obsidian.link.ReplaceOpts
---@field bufnr integer
---@field range obsidian.Range 0-based, end-exclusive byte range.
---@field text string Formatted link text.

---Replace a range with formatted link text.
---@param opts obsidian.link.ReplaceOpts
function M.replace(opts)
  local range = opts.range
  vim.api.nvim_buf_set_text(opts.bufnr, range.start_row, range.start_col, range.end_row, range.end_col, { opts.text })
end

---@class obsidian.link.InsertOpts
---@field bufnr integer
---@field pos obsidian.Pos 0-based byte position.
---@field text string Formatted link text.

---Insert formatted link text at a position.
---@param opts obsidian.link.InsertOpts
function M.insert(opts)
  local pos = opts.pos
  M.replace { bufnr = opts.bufnr, range = Range.new(pos.row, pos.col, pos.row, pos.col), text = opts.text }
end

---@class obsidian.link.UnlinkOpts
---@field bufnr integer
---@field ref obsidian.parse.Ref

---Replace a parsed link with its display text.
---@param opts obsidian.link.UnlinkOpts
---@return string? display_text
function M.unlink(opts)
  local ref, bufnr = opts.ref, opts.bufnr
  if ref.kind ~= "wiki" and ref.kind ~= "markdown" and ref.kind ~= "autolink" then
    return
  end

  local display_text = ref.label
  if not display_text or display_text == "" then
    local target = vim.uri_decode(ref.target)
    display_text = Path.new(target).stem
    if not display_text or display_text == "" then
      display_text = Path.buffer(bufnr).stem
    end
  end
  if not display_text or display_text == "" then
    return
  end

  M.replace { bufnr = bufnr, range = ref.range, text = display_text }
  return display_text
end

return M
