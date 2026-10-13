local M = {}
local responses = {}

---@param uri string?
---@param bufnr integer
---@param range lsp.Range|?
---@return string
local function response_key(uri, bufnr, range)
  return (uri or tostring(bufnr)) .. ":" .. vim.inspect(range)
end

---@param uri string?
---@param bufnr integer
---@param range lsp.Range|?
---@param opts { allow_stale: boolean? }|?
---@return lsp.InlayHint[]?
function M.get(uri, bufnr, range, opts)
  opts = opts or {}
  local key = response_key(uri, bufnr, range)
  local entry = responses[key]
  if not entry then
    return nil
  end
  if entry.generation ~= require("obsidian.cache").generation() then
    responses[key] = nil
    return nil
  end
  if
    not opts.allow_stale
    and (not vim.api.nvim_buf_is_valid(bufnr) or entry.changedtick ~= vim.api.nvim_buf_get_changedtick(bufnr))
  then
    return nil
  end
  return entry.hints
end

---@param uri string?
---@param bufnr integer
---@param range lsp.Range|?
---@param hints lsp.InlayHint[]
function M.set(uri, bufnr, range, hints)
  responses[response_key(uri, bufnr, range)] = {
    bufnr = bufnr,
    changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
    generation = require("obsidian.cache").generation(),
    hints = vim.deepcopy(hints),
  }
end

---@param bufnr integer|?
function M.invalidate(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if bufnr then
    local name = vim.api.nvim_buf_get_name(bufnr)
    local uri = name ~= "" and vim.uri_from_fname(name) or nil
    local prefix = uri and (uri .. ":") or nil
    for key, entry in pairs(responses) do
      if entry.bufnr == bufnr or (prefix and vim.startswith(key, prefix)) then
        responses[key] = nil
      end
    end
  else
    responses = {}
  end
end

return M
