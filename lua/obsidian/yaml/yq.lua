local M = {}

---@param str string
---@return any
M.loads = function(str)
  local out = vim
    .system({ "yq" }, {
      stdin = str,
    })
    :wait()
  if out.code ~= 0 then
    return nil
  end
  -- local data = vim.json.decode(out.stdout, { luanil = { object = true, array = true } })
  local data = vim.json.decode(out.stdout)
  return data
end

return M
