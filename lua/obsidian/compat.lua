local M = {}

local has_nvim_0_12 = vim.fn.has "nvim-0.12" == 1

--- Remove duplicate list values in place, preserving their first occurrence.
--- Remove on 0.13 release
---@generic T
---@param values T[]
---@param key? fun(value: T): any
---@return T[]
M.list_unique = function(values, key)
  if has_nvim_0_12 then
    return vim.list.unique(values, key)
  end

  local seen = {}
  local write = 1
  local original_length = #values
  for read = 1, original_length do
    local value = values[read]
    local unique_key = value
    if key then
      unique_key = key(value)
    end
    if unique_key == nil or not seen[unique_key] then
      values[write] = value
      if unique_key ~= nil then
        seen[unique_key] = true
      end
      write = write + 1
    end
  end
  for i = write, original_length do
    values[i] = nil
  end
  return values
end

return M
