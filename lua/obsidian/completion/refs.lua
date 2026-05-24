local util = require "obsidian.util"

local M = {}

---Backtrack through a string to find the first occurrence of '[['.
---
---@param input string
---@return string|? input
---@return string|? search
local find_search_start = function(input)
  for i = string.len(input), 1, -1 do
    local substr = string.sub(input, i)
    if vim.startswith(substr, "]") or vim.endswith(substr, "]") then
      return nil
    elseif vim.startswith(substr, "[[") then
      return substr, string.sub(substr, 3)
    end
  end
  return nil
end

---Check if a completion request can/should be carried out. Returns a boolean
---and, if true, the search string and the column indices of where the completion
---items should be inserted.
---
---@param request obsidian.completion.Request
---@return boolean can_complete
---@return string|? search_string
---@return integer|? insert_start
---@return integer|? insert_end
M.can_complete = function(request)
  local input, search = find_search_start(request.cursor_before_line)
  if input == nil or search == nil then
    return false
  elseif string.len(search) == 0 or util.is_whitespace(search) then
    return false
  end

  if vim.startswith(input, "[[") then
    local suffix = string.sub(request.cursor_after_line, 1, 2)
    local cursor_char = request.character
    local insert_end_offset = suffix == "]]" and 1 or -1
    return true, search, cursor_char - string.len(input), cursor_char + 1 + insert_end_offset
  else
    return false
  end
end

---@param label string
---@return string
M.get_filter_text = function(label)
  return "[[" .. label
end

---Collect matching block links.
---@param note obsidian.Note
---@param block_link string?
---@return obsidian.note.Block[]|?
function M.collect_matching_blocks(note, block_link)
  ---@type obsidian.note.Block[]|?
  local matching_blocks
  if block_link then
    assert(note.blocks, "no block")
    matching_blocks = {}
    for block_id, block_data in pairs(note.blocks) do
      if vim.startswith("#" .. block_id, block_link) then
        table.insert(matching_blocks, block_data)
      end
    end

    if #matching_blocks == 0 then
      -- Unmatched, create a mock one.
      table.insert(matching_blocks, { id = util.standardize_block(block_link), line = 1 })
    end
  end

  return matching_blocks
end

---Collect matching anchor links.
---@param note obsidian.Note
---@param anchor_link string?
---@return obsidian.note.HeaderAnchor[]?
function M.collect_matching_anchors(note, anchor_link)
  ---@type obsidian.note.HeaderAnchor[]|?
  local matching_anchors
  if anchor_link then
    assert(note.anchor_links, "no anchor link")
    matching_anchors = {}
    for anchor, anchor_data in pairs(note.anchor_links) do
      if vim.startswith(anchor, anchor_link) then
        table.insert(matching_anchors, anchor_data)
      end
    end

    if #matching_anchors == 0 then
      -- Unmatched, create a mock one.
      table.insert(matching_anchors, { anchor = anchor_link, header = string.sub(anchor_link, 2), level = 1, line = 1 })
    end
  end

  return matching_anchors
end

return M
