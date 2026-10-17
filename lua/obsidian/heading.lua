local Note = require "obsidian.note"

local M = {}

---@class obsidian.HeadingLocation
---@field header string
---@field level integer
---@field path string
---@field line integer 1-indexed heading start line
---@field section obsidian.Section

---Enumerate headings from the current buffer snapshot, including unsaved edits.
---@param bufnr integer|?
---@return obsidian.HeadingLocation[]
M.list = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local note = Note.from_buffer(bufnr, { collect_sections = true })
  if not note.path then
    return {}
  end

  local headings = {}
  for _, section in ipairs(note.sections or {}) do
    if section.header then
      headings[#headings + 1] = {
        header = section.header,
        level = section.level,
        path = tostring(note.path),
        line = section.heading_range.start_row + 1,
        section = section,
      }
    end
  end
  return headings
end

return M
