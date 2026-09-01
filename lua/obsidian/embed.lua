local ns_id = vim.api.nvim_create_namespace "obsidian-nvim-embeds"
local search = require "obsidian.search"
local ts = require "obsidian.ts"

local LEFT_SEP = "▏"

---@param note obsidian.Note
---@return string[]
local function note_body(note)
  local lines = {}
  local start_line = note.frontmatter_end_line and note.frontmatter_end_line + 1 or 1
  for line_num = start_line, #note.contents do
    lines[#lines + 1] = note.contents[line_num]
  end
  return lines
end

---@param note obsidian.Note
---@return table[] virt_lines
local function render_note(note)
  local virt_lines = ts.to_virt_lines(note_body(note))
  for _, line in ipairs(virt_lines) do
    table.insert(line, 1, { LEFT_SEP, "NonText" })
  end
  return virt_lines
end

---@param link string
---@return string|nil
local function note_id_from_embed(link)
  local note_id = link:match "^([^|#]+)"
  if note_id then
    note_id = vim.trim(note_id)
  end
  return note_id ~= "" and note_id or nil
end

local M = {}

---@param buf integer
M.start = function(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for line_num, line in ipairs(lines) do
    local link = line:match "!%[%[([^%]]+)%]%]"
    local note_id = link and note_id_from_embed(link)
    if note_id then
      local ok, notes = pcall(search.resolve_note, note_id, {})
      if ok and notes and notes[1] then
        local virt_lines = render_note(notes[1])
        if #virt_lines > 0 then
          vim.api.nvim_buf_set_extmark(buf, ns_id, line_num - 1, 0, {
            virt_lines = virt_lines,
          })
        end
      end
    end
  end
end

return M
