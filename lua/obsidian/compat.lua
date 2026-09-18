local M = {}

local has_nvim_0_12 = vim.fn.has "nvim-0.12" == 1

--- Remove duplicate list values in place, preserving their first occurrence.
---@generic T
---@param values T[]
---@return T[]
M.list_unique = function(values)
  if has_nvim_0_12 then
    return vim.list.unique(values)
  end

  local seen = {}
  local write = 1
  local original_length = #values
  for read = 1, original_length do
    local value = values[read]
    if not seen[value] then
      seen[value] = true
      values[write] = value
      write = write + 1
    end
  end
  for i = write, original_length do
    values[i] = nil
  end
  return values
end

return M
