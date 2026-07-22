local fragments = require "obsidian.completion.fragments"
local util = require "obsidian.util"

local M = {}

---@param request obsidian.completion.Request
---@return boolean can_complete
---@return obsidian.completion.FragmentContext|? context
function M.can_complete(request)
  local context = fragments.parse(request)
  if not context or not vim.startswith(context.fragment, "#^") then
    return false
  end
  return true, context
end

---Collect blocks matching the fragment currently being entered.
---@param note obsidian.Note
---@param block_link string
---@return obsidian.note.Block[]
function M.collect_matching(note, block_link)
  local matches = {}
  for block_id, block_data in pairs(note.blocks or {}) do
    if vim.startswith("#" .. block_id, block_link) then
      matches[#matches + 1] = block_data
    end
  end

  if #matches == 0 and #block_link > 2 then
    matches[1] = {
      id = util.standardize_block(block_link),
      block = "",
      line = 1,
    }
  end

  return matches
end

return M
