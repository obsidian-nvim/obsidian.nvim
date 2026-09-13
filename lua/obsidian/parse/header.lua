local M = {}

--- Normalize a heading anchor and ensure exactly one leading `#`.
---@param anchor string
---@return string
M.normalize_anchor = function(anchor)
  anchor = anchor:gsub("^#+", "")
  anchor = anchor:lower()
  anchor = anchor:gsub("%s", "-")
  anchor = anchor:gsub("[^#%w\128-\255_-]", "")
  return "#" .. anchor
end

--- Transform a Markdown heading or label into an anchor.
---@param header string
---@return string
M.to_anchor = function(header)
  local label = vim.trim(header:gsub([[^#+%s+]], ""))
  return M.normalize_anchor(label)
end

--- Parse an ATX Markdown heading.
---@param line string
---@return { header: string, level: integer, anchor: string }?
M.parse = function(line)
  local marker, label = line:match "^(#+)%s+([^%s]+.*)$"
  if not marker or not label then
    return nil
  end
  label = vim.trim(label)
  return {
    header = label,
    level = #marker,
    anchor = M.to_anchor(label),
  }
end

return M
