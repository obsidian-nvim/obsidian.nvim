local ns_id = vim.api.nvim_create_namespace "obsidian-nvim-embeds"
local id_counter = 0
local search = require "obsidian.search"

local LEFT_SEP = "▏"

-- <buf, <line_num, markid>>
local id_cache = vim.defaulttable()

---@param note obsidian.Note
local function compute_virt_lines(note)
  local res = {}
  local contents = note.contents

  local start_line = note.frontmatter_end_line and note.frontmatter_end_line + 1 or 0

  for lnum = start_line, #contents do
    local line = contents[lnum]
    res[#res + 1] = { { LEFT_SEP, "NonText" }, { line, "@CursorLine" } }
  end

  return res
end

---@param bnr integer
---@param line_num integer 0 based
---@param col_num integer 0 based
---@param virt_lines table
---@param id integer
local function display_result(bnr, line_num, col_num, virt_lines, id)
  local opts = {
    id = id,
    virt_lines = virt_lines,
  }
  local mark_id = vim.api.nvim_buf_set_extmark(bnr, ns_id, line_num, col_num, opts)
  return mark_id
end

local M = {}

M.start = function(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)

  for line_num, line in ipairs(lines) do
    local note_id = line:match "!%[%[(.+)%]%]"
    if note_id then
      id_counter = id_counter + 1
      local notes = search.resolve_note(note_id, {})
      if not vim.tbl_isempty(notes) then
        local virt_lines = compute_virt_lines(notes[1])
        local markid = display_result(buf, line_num - 1, 0, virt_lines, id_counter)
        id_cache[buf][line_num] = markid
      end
    end
  end
end

return M
