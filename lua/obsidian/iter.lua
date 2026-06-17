---@param ... any
---@return any
local function iter(...)
  ---@diagnostic disable-next-line: call-non-callable
  return vim.iter(...)
end

return iter
