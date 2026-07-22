local fragments = require "obsidian.completion.fragments"

local M = {}

---@param request obsidian.completion.Request
---@return boolean can_complete
---@return obsidian.completion.FragmentContext|? context
function M.can_complete(request)
  local context = fragments.parse(request)
  if not context or vim.startswith(context.fragment, "#^") then
    return false
  end
  return true, context
end

---Collect anchors matching the fragment currently being entered.
---@param note obsidian.Note
---@param anchor_link string
---@return obsidian.note.HeaderAnchor[]
function M.collect_matching(note, anchor_link)
  local matches = {}
  for anchor, anchor_data in pairs(note.anchor_links or {}) do
    if vim.startswith(anchor, anchor_link) then
      matches[#matches + 1] = anchor_data
    end
  end

  if #matches == 0 and #anchor_link > 1 then
    matches[1] = {
      anchor = anchor_link,
      header = anchor_link:sub(2),
      level = 1,
      line = 1,
    }
  end

  return matches
end

return M
